import Dependencies
import ErrorKit
import Foundation
import Logging
import MonadPrompt
import MonadShared

/// Manages conversation timelines, their associated context, and tool execution environments.
///
/// The `TimelineManager` is responsible for the lifecycle of `Timeline` objects,
/// including their creation, hydration from persistence, and cleanup. It also coordinates
/// timeline-specific components like `ContextManager` and `ToolExecutor`.
public actor TimelineManager {
    /// In-memory cache of active timelines.
    var timelines: [UUID: Timeline] = [:]

    /// Context managers responsible for RAG and context gathering for each timeline.
    var contextManagers: [UUID: ContextManager] = [:]

    /// Tool managers handling tool registration and availability for each timeline.
    var toolManagers: [UUID: TimelineToolManager] = [:]

    /// Tool executors that perform the actual tool calls for each timeline.
    var toolExecutors: [UUID: ToolExecutor] = [:]

    /// State management for tool execution context within a timeline.
    var toolContextTimelines: [UUID: ToolTimelineContext] = [:]

    /// Ongoing generation tasks for each timeline.
    var activeTasks: [UUID: Task<Void, Never>] = [:]

    @Dependency(\.timelinePersistence) var timelineStore
    @Dependency(\.messageStore) var messageStore
    @Dependency(\.workspacePersistence) var workspaceStore
    @Dependency(\.memoryStore) var memoryStore
    @Dependency(\.toolPersistence) var toolPersistence
    @Dependency(\.agentTemplateStore) var agentTemplateStore
    @Dependency(\.clientStore) var clientStore
    @Dependency(\.agentInstanceStore) var agentInstanceStore

    let vectorStore: (any VectorStoreProtocol)?
    let workspaceRoot: URL
    let connectionManager: (any ClientConnectionManagerProtocol)?
    public let workspaceManager: WorkspaceManager
    let sectionProviders: [any PromptSectionProviding]

    /// Initializes a new `TimelineManager`.
    public init(
        vectorStore: (any VectorStoreProtocol)? = nil,
        workspaceRoot: URL,
        connectionManager: (any ClientConnectionManagerProtocol)? = nil,
        workspaceCreator: any WorkspaceCreating = NullWorkspaceCreator(),
        sectionProviders: [any PromptSectionProviding] = []
    ) {
        self.vectorStore = vectorStore
        self.workspaceRoot = workspaceRoot
        self.connectionManager = connectionManager
        self.sectionProviders = sectionProviders

        workspaceManager = WorkspaceManager(
            repository: AgentWorkspaceService(workspaceRoot: workspaceRoot),
            connectionManager: connectionManager,
            workspaceCreator: workspaceCreator
        )
    }

    /// Gathers additional prompt sections from all registered `PromptSectionProviding` instances.
    public func gatherExtensionSections(
        timelineId: UUID,
        agentInstanceId: UUID?,
        message: String
    ) async -> [any ContextSection] {
        let buildContext = PromptBuildContext(
            timelineId: timelineId,
            agentInstanceId: agentInstanceId,
            message: message
        )
        var sections: [any ContextSection] = []
        for provider in sectionProviders {
            sections += await provider.sections(for: buildContext)
        }
        return sections
    }

    // MARK: - Component Setup

    /// Initializes and configures the internal components for a conversation timeline.
    func setupTimelineComponents(
        timeline: Timeline,
        workspaceURL: URL,
        parentId: UUID? = nil
    ) async {
        let contextWorkspace: (any WorkspaceProtocol)?
        if let firstId = timeline.attachedWorkspaceIds.first {
            contextWorkspace = try? await workspaceManager.getWorkspace(id: firstId)
        } else {
            contextWorkspace = nil
        }

        let contextManager = ContextManager(workspace: contextWorkspace)
        contextManagers[timeline.id] = contextManager

        let toolContextTimeline = ToolTimelineContext()
        toolContextTimelines[timeline.id] = toolContextTimeline

        let toolManager = await createToolManager(
            for: timeline, jailRoot: workspaceURL.path,
            toolContextTimeline: toolContextTimeline,
            parentId: parentId
        )
        toolManagers[timeline.id] = toolManager

        for attachedId in timeline.attachedWorkspaceIds {
            if let workspace = try? await workspaceManager.getWorkspace(id: attachedId) {
                await toolManager.registerWorkspace(workspace)
            }
        }

        let toolExecutor = ToolExecutor(
            toolManager: toolManager,
            timelineContext: toolContextTimeline
        )
        toolExecutors[timeline.id] = toolExecutor
    }

    // MARK: - Task Management

    /// Registers a generation task for a timeline, cancelling any previous active task.
    public func registerTask(_ task: Task<Void, Never>, for timelineId: UUID) {
        activeTasks[timelineId]?.cancel()
        activeTasks[timelineId] = task
    }

    /// Explicitly cancels an ongoing generation task for a timeline.
    public func cancelGeneration(for timelineId: UUID) {
        activeTasks[timelineId]?.cancel()
        activeTasks.removeValue(forKey: timelineId)
    }
}

public enum TimelineError: Throwable {
    case timelineNotFound

    public var errorDescription: String? {
        switch self {
        case .timelineNotFound:
            return "Timeline not found."
        }
    }

    public var userFriendlyMessage: String {
        switch self {
        case .timelineNotFound:
            return "The requested chat timeline could not be found."
        }
    }
}

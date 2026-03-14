import Dependencies
import ErrorKit
import Foundation
import Logging
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
    @Dependency(\.backgroundJobStore) var backgroundJobStore
    @Dependency(\.agentTemplateStore) var agentTemplateStore
    @Dependency(\.clientStore) var clientStore
    @Dependency(\.agentInstanceStore) var agentInstanceStore

    let vectorStore: (any VectorStoreProtocol)?
    let workspaceRoot: URL
    let connectionManager: (any ClientConnectionManagerProtocol)?
    public let workspaceManager: WorkspaceManager

    /// Initializes a new `TimelineManager`.
    /// - Parameters:
    ///   - vectorStore: An optional store for vector embeddings.
    ///   - workspaceRoot: The root directory where timeline data is stored.
    ///   - connectionManager: Optional manager for client-side tool connections.
    ///   - workspaceCreator: Factory for creating concrete `WorkspaceProtocol` instances.
    public init(
        vectorStore: (any VectorStoreProtocol)? = nil,
        workspaceRoot: URL,
        connectionManager: (any ClientConnectionManagerProtocol)? = nil,
        workspaceCreator: any WorkspaceCreating = NullWorkspaceCreator()
    ) {
        self.vectorStore = vectorStore
        self.workspaceRoot = workspaceRoot
        self.connectionManager = connectionManager

        // Use withDependencies to ensure repository picks up current context if needed,
        // although Dependencies usually works via property wrappers.
        workspaceManager = WorkspaceManager(
            repository: WorkspaceRepository(workspaceRoot: workspaceRoot),
            connectionManager: connectionManager,
            workspaceCreator: workspaceCreator
        )
    }

    // MARK: - Component Setup

    /// Initializes and configures the internal components for a conversation timeline.
    ///
    /// This method sets up the `ContextManager`, `ToolTimelineContext`, `TimelineToolManager`,
    /// and `ToolExecutor` for the given timeline. It also handles workspace hydration
    /// and registration.
    ///
    /// - Parameters:
    ///   - timeline: The conversation timeline to set up components for.
    ///   - workspaceURL: The file system URL for the timeline's workspace.
    ///   - parentId: An optional parent timeline ID for context inheritance.
    func setupTimelineComponents(
        timeline: Timeline,
        workspaceURL: URL,
        parentId: UUID? = nil
    ) async {
        // Use first attached workspace for ContextManager (primary concept moved to AgentInstance)
        let contextWorkspace: (any WorkspaceProtocol)?
        if let firstId = timeline.attachedWorkspaceIds.first {
            contextWorkspace = try? await workspaceManager.getWorkspace(id: firstId)
        } else {
            contextWorkspace = nil
        }

        let contextManager = ContextManager(
            workspace: contextWorkspace
        )
        contextManagers[timeline.id] = contextManager

        let toolContextTimeline = ToolTimelineContext()
        toolContextTimelines[timeline.id] = toolContextTimeline

        let jobQueueContext = BackgroundJobQueueContext(backgroundJobStore: backgroundJobStore, timelineId: timeline.id)

        // Setup Tools for timeline
        let toolManager = await createToolManager(
            for: timeline, jailRoot: workspaceURL.path,
            toolContextTimeline: toolContextTimeline,
            jobQueueContext: jobQueueContext,
            parentId: parentId
        )
        toolManagers[timeline.id] = toolManager

        // Hydrate and register all attached workspaces with ToolManager
        for attachedId in timeline.attachedWorkspaceIds {
            if let ws = try? await workspaceManager.getWorkspace(id: attachedId) {
                await toolManager.registerWorkspace(ws)
            }
        }

        let toolExecutor = ToolExecutor(
            toolManager: toolManager,
            timelineContext: toolContextTimeline,
            jobQueueContext: jobQueueContext
        )
        toolExecutors[timeline.id] = toolExecutor
    }

    // MARK: - Timeline Lifecycle

    /// Creates a new conversation timeline, initializes its workspace, and saves it to persistence.
    /// - Parameters:
    ///   - title: The initial title of the timeline.
    /// - Returns: The newly created `Timeline`.
    public func createTimeline(title: String = "New Conversation")
        async throws
        -> Timeline {
        let timelineId = UUID()

        let timelineWorkspaceURL = workspaceRoot.appendingPathComponent(
            "timelines", isDirectory: true
        )
        .appendingPathComponent(timelineId.uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: timelineWorkspaceURL, withIntermediateDirectories: true
        )

        let notesDir = timelineWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        let welcomeNote = """
        # Welcome to Your Monad Timeline

        This timeline is your private workspace. You can use the `Notes/` directory in the Primary Workspace to store information that should persist and influence your behavior across turns.

        ## System Orientation
        - Primary Workspace: Your server-side sandbox.
        - Attached Workspaces: Directories mapped during this timeline.
        - Context Depth: Use `create_memory` for long-term facts and `Notes/` for project-specific guidance.
        """
        try welcomeNote.write(to: notesDir.appendingPathComponent("Welcome.md"), atomically: true, encoding: .utf8)

        let projectNote = """
        # Project Goals & Progress

        Use this note to track the active objective and your current progress.

        ## Active Objective
        [Describe what the user wants to achieve here]

        ## Key Milestones
        - [ ] Milestone 1
        - [ ] Milestone 2

        ## Decisions & Context
        Record any critical decisions made during the timeline here.
        """
        try projectNote.write(to: notesDir.appendingPathComponent("Project.md"), atomically: true, encoding: .utf8)

        let workspace = WorkspaceReference(
            uri: .serverTimeline(timelineId),
            hostType: .server,
            rootPath: timelineWorkspaceURL.path,
            trustLevel: .full
        )

        try await workspaceStore.saveWorkspace(workspace)

        var timeline = Timeline(
            id: timelineId,
            title: title,
            attachedWorkspaceIds: [workspace.id]
        )
        timeline.workingDirectory = timelineWorkspaceURL.path

        timelines[timeline.id] = timeline
        await setupTimelineComponents(timeline: timeline, workspaceURL: timelineWorkspaceURL)
        try await timelineStore.saveTimeline(timeline)

        return timeline
    }

    /// Retrieves a timeline by its ID and updates its `updatedAt` timestamp.
    /// - Parameter id: The unique identifier of the timeline.
    /// - Returns: The `Timeline` if found, `nil` otherwise.
    public func getTimeline(id: UUID) -> Timeline? {
        guard var timeline = timelines[id] else { return nil }
        timeline.updatedAt = Date()
        timelines[id] = timeline
        return timeline
    }

    /// Reconstructs a timeline and its components from persistence.
    /// - Parameters:
    ///   - id: The timeline ID to hydrate.
    ///   - parentId: Optional parent job ID for context.
    public func hydrateTimeline(id: UUID, parentId: UUID? = nil) async throws {
        if toolExecutors[id] != nil { return }

        guard let timeline = try await timelineStore.fetchTimeline(id: id) else {
            throw TimelineError.timelineNotFound
        }

        let timelineWorkspaceURL: URL
        if let wd = timeline.workingDirectory {
            timelineWorkspaceURL = URL(fileURLWithPath: wd)
        } else {
            timelineWorkspaceURL = workspaceRoot.appendingPathComponent(
                "timelines", isDirectory: true
            ).appendingPathComponent(id.uuidString, isDirectory: true)
        }

        timelines[id] = timeline
        await setupTimelineComponents(
            timeline: timeline,
            workspaceURL: timelineWorkspaceURL,
            parentId: parentId
        )
    }

    /// Updates the title of a specific timeline.
    /// - Parameters:
    ///   - id: The timeline ID.
    ///   - title: The new title.
    public func updateTimelineTitle(id: UUID, title: String) async throws {
        var timeline: Timeline
        if let memoryTimeline = timelines[id] {
            timeline = memoryTimeline
        } else if let dbTimeline = try await timelineStore.fetchTimeline(id: id) {
            timeline = dbTimeline
        } else {
            throw TimelineError.timelineNotFound
        }

        timeline.title = title
        timeline.updatedAt = Date()

        if timelines[id] != nil {
            timelines[id] = timeline
        }
        try await timelineStore.saveTimeline(timeline)
    }

    /// Retrieves the context manager for a timeline if it is active.
    public func getContextManager(for timelineId: UUID) -> ContextManager? {
        return contextManagers[timelineId]
    }

    /// Retrieves the tool executor for a timeline if it is active.
    public func getToolExecutor(for timelineId: UUID) -> ToolExecutor? {
        return toolExecutors[timelineId]
    }

    /// Retrieves the tool manager for a timeline if it is active.
    public func getToolManager(for timelineId: UUID) -> TimelineToolManager? {
        return toolManagers[timelineId]
    }

    /// Removes a timeline and its components from memory.
    /// - Note: This does not delete the timeline from persistence.
    public func deleteTimeline(id: UUID) {
        timelines.removeValue(forKey: id)
        contextManagers.removeValue(forKey: id)
        toolManagers.removeValue(forKey: id)
        toolExecutors.removeValue(forKey: id)
        toolContextTimelines.removeValue(forKey: id)
    }

    /// Fetches the message history for a specific timeline from persistence.
    public func getHistory(for timelineId: UUID) async throws -> [Message] {
        let conversationMessages = try await messageStore.fetchMessages(for: timelineId)
        return conversationMessages.map { $0.toMessage() }
    }

    // MARK: - Agent Support

    /// Returns the agent instance attached to a timeline, cleaning up dangling references.
    public func getAttachedAgentInstance(for timelineId: UUID) async -> AgentInstance? {
        let agentId: UUID?
        if let cached = timelines[timelineId] {
            agentId = cached.attachedAgentInstanceId
        } else if let fetched = try? await timelineStore.fetchTimeline(id: timelineId) {
            agentId = fetched.attachedAgentInstanceId
        } else {
            return nil
        }

        guard let agentId else { return nil }

        if let agent = try? await agentInstanceStore.fetchAgentInstance(id: agentId) {
            return agent
        }

        // Dangling reference cleanup
        if var stale = try? await timelineStore.fetchTimeline(id: timelineId) {
            stale.attachedAgentInstanceId = nil
            try? await timelineStore.saveTimeline(stale)
            timelines[timelineId] = stale
            Logger.module(named: "timeline-manager").warning("Cleared dangling agent \(agentId) reference on timeline \(timelineId)")
        }
        return nil
    }

    /// Reads Notes/system.md from the attached agent's workspace, if any.
    public func getAgentSystemInstructions(for timelineId: UUID) async -> String? {
        guard let agent = await getAttachedAgentInstance(for: timelineId),
              let workspaceId = agent.primaryWorkspaceId,
              let workspace = try? await workspaceStore.fetchWorkspace(id: workspaceId),
              let rootPath = workspace.rootPath
        else { return nil }

        let systemMdPath = rootPath + "/Notes/system.md"
        return try? String(contentsOfFile: systemMdPath, encoding: .utf8)
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

    /// Lists all active (non-archived) timelines from persistence.
    public func listTimelines() async throws -> [Timeline] {
        return try await timelineStore.fetchAllTimelines(includeArchived: false)
    }

    /// Removes active timelines from memory that have not been updated within the specified interval.
    public func cleanupStaleTimelines(maxAge: TimeInterval) {
        let now = Date()
        let staleIds = timelines.values.filter { timeline in
            now.timeIntervalSince(timeline.updatedAt) > maxAge
        }.map { $0.id }

        for id in staleIds {
            deleteTimeline(id: id)
        }
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

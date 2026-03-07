import Dependencies
import Foundation
import Logging
import MonadShared

/// Manages the lifecycle of agent instances: creation, attachment to timelines,
/// detachment, and deletion.
///
/// Attachment rules:
/// - Each timeline can have at most one attached agent (exclusive lock).
/// - One agent can attach to multiple timelines simultaneously.
/// - `attach` is idempotent: re-attaching the same agent to the same timeline is a no-op.
/// - If `attachedAgentInstanceId` references a deleted agent, it is nulled on access.
public actor AgentInstanceManager {
    @Dependency(\.persistenceService) private var persistence

    private let workspaceRoot: URL
    private let logger = Logger.module(named: "agent-instance-manager")

    public init(workspaceRoot: URL) {
        self.workspaceRoot = workspaceRoot
    }

    // MARK: - Create

    /// Creates a new agent instance, its private workspace, and its private timeline atomically.
    /// - Parameters:
    ///   - template: Optional `MSAgent` template to seed workspace files from.
    ///   - name: Display name for the instance.
    ///   - description: Purpose description.
    /// - Returns: The created `AgentInstance`.
    public func createInstance(
        from template: MSAgent? = nil,
        name: String,
        description: String
    ) async throws -> AgentInstance {
        let instanceId = UUID()
        let privateTimelineId = UUID()

        // 1. Create workspace directory
        let agentWorkspaceURL = workspaceRoot
            .appendingPathComponent("agents", isDirectory: true)
            .appendingPathComponent(instanceId.uuidString, isDirectory: true)
        let notesDir = agentWorkspaceURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)

        // 2. Seed workspace files
        if let seed = template?.workspaceFilesSeed, !seed.isEmpty {
            for (filename, content) in seed {
                try content.write(
                    to: notesDir.appendingPathComponent(filename),
                    atomically: true,
                    encoding: .utf8
                )
            }
        } else if let template = template {
            // Default: write composed instructions as system.md
            try template.composedInstructions.write(
                to: notesDir.appendingPathComponent("system.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        // 3. Persist workspace reference
        let workspace = WorkspaceReference(
            uri: .agentWorkspace(instanceId),
            hostType: .server,
            rootPath: agentWorkspaceURL.path,
            trustLevel: .full
        )
        try await persistence.saveWorkspace(workspace)

        // 4. Persist private timeline
        let privateTimeline = Timeline(
            id: privateTimelineId,
            title: "[\(name)] Private",
            primaryWorkspaceId: workspace.id,
            isPrivate: true,
            ownerAgentInstanceId: instanceId
        )
        try await persistence.saveTimeline(privateTimeline)

        // 5. Persist agent instance
        let instance = AgentInstance(
            id: instanceId,
            name: name,
            description: description,
            primaryWorkspaceId: workspace.id,
            privateTimelineId: privateTimelineId
        )
        try await persistence.saveAgentInstance(instance)

        // 6. Log creation to private timeline
        let creationMsg = ConversationMessage(
            timelineId: privateTimelineId,
            role: .system,
            content: "[CREATED] Agent instance '\(name)' (\(instanceId.uuidString)) created."
        )
        try await persistence.saveMessage(creationMsg)

        logger.info("Created agent instance '\(name)' (\(instanceId))")
        return instance
    }

    // MARK: - Attach / Detach

    /// Attaches an agent instance to a timeline.
    ///
    /// - Idempotent: no-op if the same agent is already attached.
    /// - Fails if a different agent is attached (caller must detach it first).
    /// - If `attachedAgentInstanceId` references a non-existent agent, it is cleared automatically.
    public func attach(agentId: UUID, to timelineId: UUID) async throws {
        guard var timeline = try await persistence.fetchTimeline(id: timelineId) else {
            throw AgentInstanceError.timelineNotFound(timelineId)
        }
        guard let agent = try await persistence.fetchAgentInstance(id: agentId) else {
            throw AgentInstanceError.instanceNotFound(agentId)
        }

        // Idempotent
        if timeline.attachedAgentInstanceId == agentId { return }

        // Check for existing attachment
        if let existingId = timeline.attachedAgentInstanceId {
            if try await persistence.fetchAgentInstance(id: existingId) != nil {
                throw AgentInstanceError.differentAgentAlreadyAttached(existingId)
            }
            // Dangling reference — clear it with a warning
            logger.warning("Clearing dangling agent reference \(existingId) on timeline \(timelineId)")
        }

        timeline.attachedAgentInstanceId = agentId
        timeline.updatedAt = Date()
        try await persistence.saveTimeline(timeline)

        // Log to agent's private timeline
        let logMsg = ConversationMessage(
            timelineId: agent.privateTimelineId,
            role: .system,
            content: "[ATTACH] timeline \"\(timeline.title)\" (\(timelineId.uuidString))"
        )
        try? await persistence.saveMessage(logMsg)

        logger.info("Agent '\(agent.name)' attached to timeline '\(timeline.title)'")
    }

    /// Detaches an agent instance from a timeline.
    /// No-op if the agent is not attached to that timeline.
    public func detach(agentId: UUID, from timelineId: UUID) async throws {
        guard var timeline = try await persistence.fetchTimeline(id: timelineId) else {
            throw AgentInstanceError.timelineNotFound(timelineId)
        }

        guard timeline.attachedAgentInstanceId == agentId else { return }

        timeline.attachedAgentInstanceId = nil
        timeline.updatedAt = Date()
        try await persistence.saveTimeline(timeline)

        // Log to agent's private timeline if it still exists
        if let agent = try? await persistence.fetchAgentInstance(id: agentId) {
            let logMsg = ConversationMessage(
                timelineId: agent.privateTimelineId,
                role: .system,
                content: "[DETACH] timeline \"\(timeline.title)\" (\(timelineId.uuidString))"
            )
            try? await persistence.saveMessage(logMsg)
            logger.info("Agent '\(agent.name)' detached from timeline '\(timeline.title)'")
        }
    }

    // MARK: - Queries

    /// Returns the agent instance attached to a timeline, or nil.
    /// Clears dangling references if the referenced agent no longer exists.
    public func getAttachedAgent(for timelineId: UUID) async -> AgentInstance? {
        guard let timeline = try? await persistence.fetchTimeline(id: timelineId),
              let agentId = timeline.attachedAgentInstanceId else { return nil }

        if let agent = try? await persistence.fetchAgentInstance(id: agentId) {
            return agent
        }

        // Dangling reference — clear it
        if var stale = try? await persistence.fetchTimeline(id: timelineId) {
            stale.attachedAgentInstanceId = nil
            try? await persistence.saveTimeline(stale)
            logger.warning("Cleared dangling agent \(agentId) reference on timeline \(timelineId)")
        }
        return nil
    }

    public func getInstance(id: UUID) async throws -> AgentInstance? {
        try await persistence.fetchAgentInstance(id: id)
    }

    public func listInstances() async throws -> [AgentInstance] {
        try await persistence.fetchAllAgentInstances()
    }

    public func getTimelines(attachedTo agentId: UUID) async throws -> [Timeline] {
        try await persistence.fetchTimelines(attachedToAgent: agentId)
    }

    public func updateInstance(_ instance: AgentInstance) async throws {
        var updated = instance
        updated.updatedAt = Date()
        try await persistence.saveAgentInstance(updated)
    }

    // MARK: - Delete

    /// Deletes an agent instance and optionally force-detaches it from all timelines.
    /// - Parameter force: If false, throws if the agent is still attached to any timelines.
    public func deleteInstance(id: UUID, force: Bool = false) async throws {
        let attachedTimelines = try await persistence.fetchTimelines(attachedToAgent: id)

        if !attachedTimelines.isEmpty, !force {
            throw AgentInstanceError.hasAttachedTimelines(count: attachedTimelines.count)
        }

        // Force-detach all timelines
        for var timeline in attachedTimelines {
            timeline.attachedAgentInstanceId = nil
            timeline.updatedAt = Date()
            try await persistence.saveTimeline(timeline)
        }

        try await persistence.deleteAgentInstance(id: id)
        logger.info("Deleted agent instance \(id)")
    }
}

// MARK: - Errors

public enum AgentInstanceError: LocalizedError, Sendable {
    case instanceNotFound(UUID)
    case timelineNotFound(UUID)
    case differentAgentAlreadyAttached(UUID)
    case hasAttachedTimelines(count: Int)

    public var errorDescription: String? {
        switch self {
        case let .instanceNotFound(id):
            return "Agent instance not found: \(id)"
        case let .timelineNotFound(id):
            return "Timeline not found: \(id)"
        case let .differentAgentAlreadyAttached(id):
            return "A different agent (\(id)) is already attached. Detach it first."
        case let .hasAttachedTimelines(count):
            return "Cannot delete: \(count) timeline(s) still attached. Use force=true to override."
        }
    }
}

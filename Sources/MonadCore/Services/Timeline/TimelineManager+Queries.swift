import Foundation
import Logging
import MonadShared

// MARK: - Timeline Queries & Agent Support

public extension TimelineManager {
    /// Retrieves a timeline by its ID and updates its `updatedAt` timestamp.
    func getTimeline(id: UUID) -> Timeline? {
        guard var timeline = timelines[id] else { return nil }
        timeline.updatedAt = Date()
        timelines[id] = timeline
        return timeline
    }

    /// Retrieves the context manager for a timeline if it is active.
    func getContextManager(for timelineId: UUID) -> ContextManager? {
        return contextManagers[timelineId]
    }

    /// Retrieves the tool executor for a timeline if it is active.
    func getToolExecutor(for timelineId: UUID) -> ToolExecutor? {
        return toolExecutors[timelineId]
    }

    /// Retrieves the tool manager for a timeline if it is active.
    func getToolManager(for timelineId: UUID) -> TimelineToolManager? {
        return toolManagers[timelineId]
    }

    /// Fetches the message history for a specific timeline from persistence.
    func getHistory(for timelineId: UUID) async throws -> [Message] {
        let conversationMessages = try await messageStore.fetchMessages(for: timelineId)
        return conversationMessages.map { $0.toMessage() }
    }

    /// Lists all active (non-archived) timelines from persistence.
    func listTimelines() async throws -> [Timeline] {
        return try await timelineStore.fetchAllTimelines(includeArchived: false)
    }

    // MARK: - Agent Support

    /// Returns the agent instance attached to a timeline, cleaning up dangling references.
    func getAttachedAgentInstance(for timelineId: UUID) async -> AgentInstance? {
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
        await cleanupDanglingAgentReference(timelineId: timelineId, agentId: agentId)
        return nil
    }

    /// Reads Notes/system.md from the attached agent's workspace, if any.
    func getAgentSystemInstructions(for timelineId: UUID) async -> String? {
        guard let agent = await getAttachedAgentInstance(for: timelineId),
              let workspaceId = agent.primaryWorkspaceId,
              let workspace = try? await workspaceStore.fetchWorkspace(id: workspaceId, includeTools: false),
              let rootPath = workspace.rootPath
        else { return nil }

        let systemMdPath = rootPath + "/Notes/system.md"
        return try? String(contentsOfFile: systemMdPath, encoding: .utf8)
    }

    // MARK: - Private Agent Helpers

    internal func cleanupDanglingAgentReference(timelineId: UUID, agentId: UUID) async {
        if var stale = try? await timelineStore.fetchTimeline(id: timelineId) {
            stale.attachedAgentInstanceId = nil
            try? await timelineStore.saveTimeline(stale)
            timelines[timelineId] = stale
            Logger.module(named: "timeline-manager").warning(
                "Cleared dangling agent \(agentId) reference on timeline \(timelineId)"
            )
        }
    }
}

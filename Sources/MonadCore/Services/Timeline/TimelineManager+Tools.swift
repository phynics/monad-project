import Foundation
import MonadShared

public extension TimelineManager {
    // MARK: - Tool Management

    internal func createToolManager(
        for session: Timeline,
        jailRoot: String,
        toolContextTimeline: ToolTimelineContext,
        jobQueueContext: BackgroundJobQueueContext,
        parentId: UUID? = nil
    ) async -> TimelineToolManager {
        let currentWD = session.workingDirectory ?? jailRoot

        var availableTools: [AnyTool] = [
            // Filesystem Tools
            AnyTool(ChangeDirectoryTool(
                currentPath: currentWD,
                root: jailRoot,
                onChange: { _ in
                    // Update working directory logic
                }
            )),
            AnyTool(ListDirectoryTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(FindFileTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(SearchFileContentTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(SearchFilesTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(ReadFileTool(currentDirectory: currentWD, jailRoot: jailRoot)),

            // MSAgent Coordination
            AnyTool(LaunchSubagentTool(
                backgroundJobStore: backgroundJobStore,
                messageStore: messageStore,
                timelineId: session.id,
                parentId: parentId,
                msAgentRegistry: msAgentRegistry
            )),

            // BackgroundJob Queue Gateway
            AnyTool(BackgroundJobQueueGatewayTool(context: jobQueueContext, timelineContext: toolContextTimeline)),

            // Timeline Observation Tools (always available)
            AnyTool(TimelineListTool(timelineStore: timelineStore)),
            AnyTool(TimelinePeekTool(messageStore: messageStore, timelineStore: timelineStore)),
        ]

        // Timeline Send: only available when an agent is attached (needs sender identity)
        if let agentId = session.attachedAgentInstanceId {
            availableTools.append(AnyTool(TimelineSendTool(
                messageStore: messageStore,
                timelineStore: timelineStore,
                agentInstanceId: agentId
            )))
        }

        return TimelineToolManager(
            availableTools: availableTools, timelineContext: toolContextTimeline
        )
    }

    /// Returns the set of system tools available to any session, using the workspace root as a
    /// placeholder path. Intended for metadata queries (listing), not actual execution.
    func systemTools() async -> [AnyTool] {
        let jailRoot = workspaceRoot.path
        let dummyId = UUID()
        let toolTimelineContext = ToolTimelineContext()
        let jobQueueContext = BackgroundJobQueueContext(backgroundJobStore: backgroundJobStore, timelineId: dummyId)
        let dummyTimeline = Timeline(id: dummyId, workingDirectory: jailRoot)
        let manager = await createToolManager(
            for: dummyTimeline,
            jailRoot: jailRoot,
            toolContextTimeline: toolTimelineContext,
            jobQueueContext: jobQueueContext
        )
        return await manager.getAvailableTools()
    }

    func findWorkspaceForTool(_ tool: ToolReference, in workspaceIds: [UUID]) async throws
        -> UUID?
    {
        return try await toolPersistence.findWorkspaceId(forToolId: tool.toolId, in: workspaceIds)
    }

    func getAggregatedTools(for timelineId: UUID) async throws -> [ToolReference] {
        guard let timeline = timelines[timelineId] else { return [] }

        var ids: [UUID] = []
        if let primaryId = timeline.primaryWorkspaceId { ids.append(primaryId) }
        ids.append(contentsOf: timeline.attachedWorkspaces)

        let workspaceIds = ids
        guard !workspaceIds.isEmpty else { return [] }

        return try await toolPersistence.fetchTools(forWorkspaces: workspaceIds)
    }

    func getClientTools(clientId: UUID) async throws -> [ToolReference] {
        return try await clientStore.fetchClientTools(clientId: clientId)
    }

    /// Aggregates all available tool references for a session, including those from the client.
    func getAllToolReferences(timelineId: UUID, clientTools: [ToolReference]? = nil) async throws -> [ToolReference] {
        var references = try await getAggregatedTools(for: timelineId)

        if let clientTools = clientTools {
            references.append(contentsOf: clientTools)
        }

        // Deduplicate by ID
        var seenIds = Set<String>()
        return references.filter { ref in
            if seenIds.contains(ref.toolId) { return false }
            seenIds.insert(ref.toolId)
            return true
        }
    }

    func getToolSource(toolId: String, for timelineId: UUID) async -> String? {
        guard let timeline = timelines[timelineId] else { return nil }

        if let toolManager = toolManagers[timelineId] {
            let systemTools = await toolManager.getAvailableTools()
            if systemTools.contains(where: { $0.id == toolId }) {
                return "System"
            }
        }

        var ids: [UUID] = []
        if let primaryId = timeline.primaryWorkspaceId { ids.append(primaryId) }
        ids.append(contentsOf: timeline.attachedWorkspaces)

        return try? await toolPersistence.fetchToolSource(
            toolId: toolId,
            workspaceIds: ids,
            primaryWorkspaceId: timeline.primaryWorkspaceId
        )
    }
}

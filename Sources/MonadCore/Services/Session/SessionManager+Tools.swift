import MonadShared
import Foundation


extension SessionManager {
    // MARK: - Tool Management

    internal func createToolManager(
        for session: ConversationSession,
        jailRoot: String,
        toolContextSession: ToolContextSession,
        jobQueueContext: JobQueueContext,
        parentId: UUID? = nil
    ) async -> SessionToolManager {
        let currentWD = session.workingDirectory ?? jailRoot

        let availableTools: [AnyTool] = [
            // Filesystem Tools
            AnyTool(ChangeDirectoryTool(
                currentPath: currentWD,
                root: jailRoot,
                onChange: { newPath in
                    // Update working directory logic
                })),
            AnyTool(ListDirectoryTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(FindFileTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(SearchFileContentTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(SearchFilesTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            AnyTool(ReadFileTool(currentDirectory: currentWD, jailRoot: jailRoot)),
            
            // Agent Coordination
            AnyTool(LaunchSubagentTool(
                persistenceService: persistenceService,
                sessionId: session.id,
                parentId: parentId,
                agentRegistry: agentRegistry
            )),
            
            // Job Queue Gateway
            AnyTool(JobQueueGatewayTool(context: jobQueueContext, contextSession: toolContextSession)),
        ]

        return SessionToolManager(
            availableTools: availableTools, contextSession: toolContextSession)
    }

    public func findWorkspaceForTool(_ tool: ToolReference, in workspaceIds: [UUID]) async throws
        -> UUID?
    {
        return try await persistenceService.findWorkspaceId(forToolId: tool.toolId, in: workspaceIds)
    }

    public func getAggregatedTools(for sessionId: UUID) async throws -> [ToolReference] {
        guard let session = sessions[sessionId] else { return [] }

        var ids: [UUID] = []
        if let p = session.primaryWorkspaceId { ids.append(p) }
        ids.append(contentsOf: session.attachedWorkspaces)

        let workspaceIds = ids
        guard !workspaceIds.isEmpty else { return [] }

        return try await persistenceService.fetchTools(forWorkspaces: workspaceIds)
    }

    public func getClientTools(clientId: UUID) async throws -> [ToolReference] {
        return try await persistenceService.fetchClientTools(clientId: clientId)
    }

    /// Aggregates all available tool references for a session, including those from the client.
    public func getAllToolReferences(sessionId: UUID, clientId: UUID? = nil) async throws -> [ToolReference] {
        var references = try await getAggregatedTools(for: sessionId)
        
        if let clientId = clientId {
            let clientTools = try await getClientTools(clientId: clientId)
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

    public func getToolSource(toolId: String, for sessionId: UUID) async -> String? {
        guard let session = sessions[sessionId] else { return nil }

        if let toolManager = toolManagers[sessionId] {
            let systemTools = await toolManager.availableTools
            if systemTools.contains(where: { $0.id == toolId }) {
                return "System"
            }
        }

        var ids: [UUID] = []
        if let p = session.primaryWorkspaceId { ids.append(p) }
        ids.append(contentsOf: session.attachedWorkspaces)

        return try? await persistenceService.fetchToolSource(
            toolId: toolId,
            workspaceIds: ids,
            primaryWorkspaceId: session.primaryWorkspaceId
        )
    }
}

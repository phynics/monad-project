import MonadShared
import Foundation
import GRDB

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
        return try await persistenceService.databaseWriter.read { db in
            let toolId = tool.toolId
            let exists =
                try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db)

            return exists?.workspaceId
        }
    }

    public func getAggregatedTools(for sessionId: UUID) async throws -> [ToolReference] {
        guard let session = sessions[sessionId] else { return [] }

        var ids: [UUID] = []
        if let p = session.primaryWorkspaceId { ids.append(p) }
        ids.append(contentsOf: session.attachedWorkspaces)

        let workspaceIds = ids
        guard !workspaceIds.isEmpty else { return [] }

        return try await persistenceService.databaseWriter.read { db in
            let tools =
                try WorkspaceTool
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)

            return try tools.map { try $0.toToolReference() }
        }
    }

    public func getClientTools(clientId: UUID) async throws -> [ToolReference] {
        return try await persistenceService.databaseWriter.read { db in
            let workspaces = try WorkspaceReference
                .filter(Column("ownerId") == clientId)
                .fetchAll(db)
            
            let workspaceIds = workspaces.map { $0.id }
            guard !workspaceIds.isEmpty else { return [] }

            let tools = try WorkspaceTool
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)

            return try tools.map { try $0.toToolReference() }
        }
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

        let workspaceIds = ids
        if workspaceIds.isEmpty { return nil }

        return try? await persistenceService.databaseWriter.read { db -> String? in
            if let toolRecord =
                try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db),
                let ws = try WorkspaceReference.fetchOne(db, key: toolRecord.workspaceId)
            {
                if ws.hostType == .client {
                    if let owner = ws.ownerId,
                        let client = try? ClientIdentity.fetchOne(db, key: owner)
                    {
                        return "Client: \(client.hostname)"
                    }
                    return "Client Workspace"
                } else if session.primaryWorkspaceId == ws.id {
                    return "Primary Workspace"
                } else {
                    return "Workspace: \(ws.uri.description)"
                }
            }
            return nil
        }
    }
}

import Foundation
import GRDB
import MonadCore
import MonadShared

public actor ToolDataRepository: ToolPersistenceProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws {
        try await dbQueue.write { db in
            guard try WorkspaceReference.exists(db, key: workspaceId) else {
                throw ToolError.workspaceNotFound(workspaceId)
            }
            let workspaceTool = try WorkspaceTool(workspaceId: workspaceId, toolReference: tool)
            try workspaceTool.insert(db)
        }
    }

    public func syncTools(workspaceId: UUID, tools: [ToolReference]) async throws {
        try await dbQueue.write { db in
            guard try WorkspaceReference.exists(db, key: workspaceId) else {
                throw ToolError.workspaceNotFound(workspaceId)
            }

            let incomingIds = Set(tools.map { $0.toolId })

            let existing = try WorkspaceTool
                .filter(Column("workspaceId") == workspaceId)
                .fetchAll(db)

            for record in existing where !incomingIds.contains(record.toolId) {
                try record.delete(db)
            }

            let existingIds = Set(existing.map { $0.toolId })
            for tool in tools where !existingIds.contains(tool.toolId) {
                let workspaceTool = try WorkspaceTool(workspaceId: workspaceId, toolReference: tool)
                try workspaceTool.insert(db)
            }
        }
    }

    public func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] {
        guard !workspaceIds.isEmpty else { return [] }
        return try await dbQueue.read { db in
            let tools = try WorkspaceTool
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)
            return try tools.map { try $0.toToolReference() }
        }
    }

    public func fetchClientTools(clientId: UUID) async throws -> [ToolReference] {
        return try await dbQueue.read { db in
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

    public func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? {
        try await dbQueue.read { db in
            let exists = try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db)
            return exists?.workspaceId
        }
    }

    public func fetchToolSource(
        toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?
    ) async throws -> String? {
        if workspaceIds.isEmpty { return nil }
        return try await dbQueue.read { db -> String? in
            if let toolRecord = try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db),
                let workspace = try WorkspaceReference.fetchOne(db, key: toolRecord.workspaceId) {
                if workspace.hostType == .client {
                    if let owner = workspace.ownerId,
                       let client = try? ClientIdentity.fetchOne(db, key: owner) {
                        return "Client: \(client.hostname)"
                    }
                    return "Client Workspace"
                } else if primaryWorkspaceId == workspace.id {
                    return "Primary Workspace"
                } else {
                    return "Workspace: \(workspace.uri.description)"
                }
            }
            return nil
        }
    }
}

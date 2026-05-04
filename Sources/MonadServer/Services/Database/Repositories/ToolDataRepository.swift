import Foundation
import GRDB
import PositronicKit
import PKShared
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

            let existing = try WorkspaceToolRecord
                .filter(Column("workspaceId") == workspaceId)
                .filter(Column("toolId") == tool.toolId)
                .fetchOne(db)
            guard existing == nil else {
                return
            }

            let workspaceTool = try WorkspaceToolRecord(workspaceId: workspaceId, toolReference: tool)
            try workspaceTool.insert(db)
        }
    }

    public func syncTools(workspaceId: UUID, tools: [ToolReference]) async throws {
        try await dbQueue.write { db in
            guard try WorkspaceReference.exists(db, key: workspaceId) else {
                throw ToolError.workspaceNotFound(workspaceId)
            }

            let incomingIds = Set(tools.map { $0.toolId })

            let existing = try WorkspaceToolRecord
                .filter(Column("workspaceId") == workspaceId)
                .fetchAll(db)

            for record in existing where !incomingIds.contains(record.toolId) {
                try record.delete(db)
            }

            let existingIds = Set(existing.map { $0.toolId })
            for tool in tools where !existingIds.contains(tool.toolId) {
                let workspaceTool = try WorkspaceToolRecord(workspaceId: workspaceId, toolReference: tool)
                try workspaceTool.insert(db)
            }
        }
    }

    public func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] {
        guard !workspaceIds.isEmpty else { return [] }
        return try await dbQueue.read { db in
            let tools = try WorkspaceToolRecord
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)
            return try tools.map { try $0.toToolReference() }
        }
    }

    public func fetchClientTools(clientId: UUID) async throws -> [ToolReference] {
        return try await dbQueue.read { db in
            let workspaces = try WorkspaceReference
                .filter(Column("originId") == clientId)
                .fetchAll(db)

            let workspaceIds = workspaces.map { $0.id }
            guard !workspaceIds.isEmpty else { return [] }

            let tools = try WorkspaceToolRecord
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)

            return try tools.map { try $0.toToolReference() }
        }
    }

    public func fetchOriginTools(originId: UUID) async throws -> [ToolReference] {
        try await fetchClientTools(clientId: originId)
    }

    public func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? {
        try await dbQueue.read { db in
            let exists = try WorkspaceToolRecord
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
            if let toolRecord = try WorkspaceToolRecord
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db),
                let workspace = try WorkspaceReference.fetchOne(db, key: toolRecord.workspaceId) {
                if workspace.location == .attached {
                    if let originId = workspace.originId,
                       let origin = try? RequestOriginIdentity.fetchOne(db, key: originId) {
                        return "Client: \(origin.hostname)"
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

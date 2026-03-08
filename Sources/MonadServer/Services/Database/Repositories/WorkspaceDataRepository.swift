import GRDB
import MonadCore
import MonadShared
import Foundation

public actor WorkspaceDataRepository: WorkspacePersistenceProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveWorkspace(_ workspace: WorkspaceReference) async throws {
        try await dbQueue.write { db in
            try workspace.save(db)
        }
    }

    public func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? {
        try await dbQueue.read { db in
            try WorkspaceReference.fetchOne(db, key: id)
        }
    }

    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] {
        try await dbQueue.read { db in
            try WorkspaceReference.fetchAll(db)
        }
    }

    public func deleteWorkspace(id: UUID) async throws {
        _ = try await dbQueue.write { db in
             try WorkspaceReference.deleteOne(db, key: id)
        }
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
            for tool in tools {
                if !existingIds.contains(tool.toolId) {
                    let workspaceTool = try WorkspaceTool(workspaceId: workspaceId, toolReference: tool)
                    try workspaceTool.insert(db)
                }
            }
        }
    }

    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? {
        try await dbQueue.read { db in
            guard let workspace = try WorkspaceReference.fetchOne(db, key: id) else {
                return nil
            }

            if includeTools {
                let workspaceTools = try WorkspaceTool
                    .filter(Column("workspaceId") == id)
                    .fetchAll(db)

                let toolRefs = workspaceTools.compactMap { try? $0.toToolReference() }

                return WorkspaceReference(
                    id: workspace.id,
                    uri: workspace.uri,
                    hostType: workspace.hostType,
                    ownerId: workspace.ownerId,
                    tools: toolRefs,
                    rootPath: workspace.rootPath,
                    trustLevel: workspace.trustLevel,
                    lastModifiedBy: workspace.lastModifiedBy,
                    status: workspace.status,
                    createdAt: workspace.createdAt
                )
            }
            return workspace
        }
    }
}

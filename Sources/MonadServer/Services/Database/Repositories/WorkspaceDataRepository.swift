import Foundation
import GRDB
import MonadCore
import MonadShared

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

    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? {
        try await dbQueue.read { db in
            guard let workspace = try WorkspaceReference.fetchOne(db, key: id) else {
                return nil
            }

            if includeTools {
                let workspaceTools = try WorkspaceTool
                    .filter(Column("workspaceId") == id)
                    .fetchAll(db)

                let toolRefs = try workspaceTools.map { try $0.toToolReference() }
                return workspace.withTools(toolRefs)
            }
            return workspace
        }
    }
}

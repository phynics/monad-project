import GRDB
import PositronicKit
import PKShared
import MonadShared
import Foundation

public actor RequestOriginRepository: RequestOriginStoreProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveOrigin(_ origin: RequestOriginIdentity) async throws {
        try await dbQueue.write { db in
            try origin.save(db)
        }
    }

    public func fetchOrigin(id: UUID) async throws -> RequestOriginIdentity? {
        try await dbQueue.read { db in
            try RequestOriginIdentity.fetchOne(db, key: id)
        }
    }

    public func fetchAllOrigins() async throws -> [RequestOriginIdentity] {
        try await dbQueue.read { db in
            try RequestOriginIdentity.fetchAll(db)
        }
    }

    public func deleteOrigin(id: UUID) async throws -> Bool {
        try await dbQueue.write { db in
            try RequestOriginIdentity.deleteOne(db, key: id)
        }
    }

    public func fetchOriginTools(originId: UUID) async throws -> [ToolReference] {
        return try await dbQueue.read { db in
            let workspaces = try WorkspaceReference
                .filter(Column("originId") == originId)
                .fetchAll(db)

            let workspaceIds = workspaces.map { $0.id }
            guard !workspaceIds.isEmpty else { return [] }

            let tools = try WorkspaceTool
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)

            return try tools.map { try $0.toToolReference() }
        }
    }
}

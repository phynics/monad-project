import GRDB
import MonadCore
import MonadShared
import Foundation

public actor ClientIdentityRepository: ClientStoreProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveClient(_ client: ClientIdentity) async throws {
        try await dbQueue.write { db in
            try client.save(db)
        }
    }

    public func fetchClient(id: UUID) async throws -> ClientIdentity? {
        try await dbQueue.read { db in
            try ClientIdentity.fetchOne(db, key: id)
        }
    }

    public func fetchAllClients() async throws -> [ClientIdentity] {
        try await dbQueue.read { db in
            try ClientIdentity.fetchAll(db)
        }
    }

    public func deleteClient(id: UUID) async throws -> Bool {
        try await dbQueue.write { db in
            try ClientIdentity.deleteOne(db, key: id)
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
}

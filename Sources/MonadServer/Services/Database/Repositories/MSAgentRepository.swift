import GRDB
import MonadCore
import MonadShared
import Foundation

public actor MSAgentRepository: MSAgentStoreProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveMSAgent(_ agent: MSAgent) async throws {
        try await dbQueue.write { db in
            try agent.save(db)
        }
    }

    public func fetchMSAgent(id: UUID) async throws -> MSAgent? {
        try await dbQueue.read { db in
            try MSAgent.fetchOne(db, key: id)
        }
    }

    public func fetchMSAgent(key: String) async throws -> MSAgent? {
         try await dbQueue.read { db in
             if let uuid = UUID(uuidString: key) {
                 return try MSAgent.fetchOne(db, key: uuid)
             }
             return nil
         }
    }

    public func fetchAllMSAgents() async throws -> [MSAgent] {
        try await dbQueue.read { db in
            try MSAgent.fetchAll(db)
        }
    }

    public func hasMSAgent(id: String) async -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }
        return await (try? dbQueue.read { db in
            try MSAgent.exists(db, key: uuid)
        }) ?? false
    }
}

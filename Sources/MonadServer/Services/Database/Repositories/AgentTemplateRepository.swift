import GRDB
import MonadCore
import MonadShared
import Foundation

public actor AgentTemplateRepository: AgentTemplateStoreProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveAgentTemplate(_ agent: AgentTemplate) async throws {
        try await dbQueue.write { db in
            try agent.save(db)
        }
    }

    public func fetchAgentTemplate(id: UUID) async throws -> AgentTemplate? {
        try await dbQueue.read { db in
            try AgentTemplate.fetchOne(db, key: id)
        }
    }

    public func fetchAgentTemplate(key: String) async throws -> AgentTemplate? {
         try await dbQueue.read { db in
             if let uuid = UUID(uuidString: key) {
                 return try AgentTemplate.fetchOne(db, key: uuid)
             }
             return nil
         }
    }

    public func fetchAllAgentTemplates() async throws -> [AgentTemplate] {
        try await dbQueue.read { db in
            try AgentTemplate.fetchAll(db)
        }
    }

    public func hasAgentTemplate(id: String) async -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }
        return await (try? dbQueue.read { db in
            try AgentTemplate.exists(db, key: uuid)
        }) ?? false
    }
}

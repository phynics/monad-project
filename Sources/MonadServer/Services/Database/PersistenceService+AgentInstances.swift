import Foundation
import GRDB
import MonadCore
import MonadShared

extension PersistenceService: AgentInstanceStoreProtocol {
    public func saveAgentInstance(_ instance: AgentInstance) throws {
        try dbQueue.write { db in try instance.save(db) }
    }

    public func fetchAgentInstance(id: UUID) throws -> AgentInstance? {
        try dbQueue.read { db in try AgentInstance.fetchOne(db, key: id) }
    }

    public func fetchAllAgentInstances() throws -> [AgentInstance] {
        try dbQueue.read { db in
            try AgentInstance.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func deleteAgentInstance(id: UUID) throws {
        _ = try dbQueue.write { db in try AgentInstance.deleteOne(db, key: id) }
    }

    public func fetchTimelines(attachedToAgent agentInstanceId: UUID) throws -> [Timeline] {
        try dbQueue.read { db in
            try Timeline
                .filter(Column("attachedAgentInstanceId") == agentInstanceId)
                .fetchAll(db)
        }
    }
}

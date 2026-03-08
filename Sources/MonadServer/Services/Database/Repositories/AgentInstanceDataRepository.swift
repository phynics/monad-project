import GRDB
import MonadCore
import MonadShared
import Foundation

public actor AgentInstanceDataRepository: AgentInstanceStoreProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func saveAgentInstance(_ instance: AgentInstance) async throws {
        try await dbQueue.write { db in try instance.save(db) }
    }

    public func fetchAgentInstance(id: UUID) async throws -> AgentInstance? {
        try await dbQueue.read { db in try AgentInstance.fetchOne(db, key: id) }
    }

    public func fetchAllAgentInstances() async throws -> [AgentInstance] {
        try await dbQueue.read { db in
            try AgentInstance.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    public func deleteAgentInstance(id: UUID) async throws {
        _ = try await dbQueue.write { db in try AgentInstance.deleteOne(db, key: id) }
    }

    public func fetchTimelines(attachedToAgent agentInstanceId: UUID) async throws -> [Timeline] {
        try await dbQueue.read { db in
            try Timeline
                .filter(Column("attachedAgentInstanceId") == agentInstanceId)
                .fetchAll(db)
        }
    }
}

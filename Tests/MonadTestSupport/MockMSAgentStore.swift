import MonadShared
import MonadCore
import Foundation

public final class MockMSAgentStore: MSAgentStoreProtocol, @unchecked Sendable {
    public var msAgents: [MSAgent] = []

    public init() {}

    public func saveMSAgent(_ agent: MSAgent) async throws {
        if let index = msAgents.firstIndex(where: { $0.id == agent.id }) {
            msAgents[index] = agent
        } else {
            msAgents.append(agent)
        }
    }

    public func fetchMSAgent(id: UUID) async throws -> MSAgent? {
        return msAgents.first(where: { $0.id == id })
    }

    public func fetchMSAgent(key: String) async throws -> MSAgent? {
        if key == "default" {
            return msAgents.first
        }
        if let uuid = UUID(uuidString: key) {
            return msAgents.first(where: { $0.id == uuid })
        }
        return nil
    }

    public func fetchAllMSAgents() async throws -> [MSAgent] {
        return msAgents
    }

    public func hasMSAgent(id: String) async -> Bool {
        if let uuid = UUID(uuidString: id) {
             return msAgents.contains(where: { $0.id == uuid })
        }
        return false
    }
}

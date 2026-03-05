@testable import MonadCore
import Foundation

public final class MockAgentStore: AgentStoreProtocol, @unchecked Sendable {
    public var agents: [Agent] = []

    public init() {}

    public func saveAgent(_ agent: Agent) async throws {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
    }

    public func fetchAgent(id: UUID) async throws -> Agent? {
        return agents.first(where: { $0.id == id })
    }

    public func fetchAgent(key: String) async throws -> Agent? {
        if key == "default" {
            return agents.first
        }
        if let uuid = UUID(uuidString: key) {
            return agents.first(where: { $0.id == uuid })
        }
        return nil
    }

    public func fetchAllAgents() async throws -> [Agent] {
        return agents
    }

    public func hasAgent(id: String) async -> Bool {
        if let uuid = UUID(uuidString: id) {
             return agents.contains(where: { $0.id == uuid })
        }
        return false
    }
}

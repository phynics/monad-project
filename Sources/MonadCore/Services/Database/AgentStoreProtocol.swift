import Foundation
import MonadShared

public protocol AgentStoreProtocol: Sendable {
    func saveAgent(_ agent: Agent) async throws
    func fetchAgent(id: UUID) async throws -> Agent?
    func fetchAgent(key: String) async throws -> Agent?
    func fetchAllAgents() async throws -> [Agent]
    func hasAgent(id: String) async -> Bool
}

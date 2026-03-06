/// Protocol for managing MSAgent definitions in persistent storage.

import Foundation

public protocol MSAgentStoreProtocol: Sendable {
    func saveMSAgent(_ agent: MSAgent) async throws
    func fetchMSAgent(id: UUID) async throws -> MSAgent?
    func fetchMSAgent(key: String) async throws -> MSAgent?
    func fetchAllMSAgents() async throws -> [MSAgent]
    func hasMSAgent(id: String) async -> Bool
}

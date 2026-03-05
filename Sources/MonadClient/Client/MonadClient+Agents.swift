import Foundation
import MonadCore

public extension MonadClient {
    // MARK: - Agent API

    /// List all registered agents
    func listAgents() async throws -> [Agent] {
        let request = try buildRequest(path: "/api/agents", method: "GET")
        return try await perform(request)
    }

    /// Get a specific agent by ID
    func getAgent(id: String) async throws -> Agent {
        let request = try buildRequest(path: "/api/agents/\(id)", method: "GET")
        return try await perform(request)
    }
}

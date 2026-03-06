import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - Agent API

    /// List all registered agents
    func listAgents() async throws -> [Agent] {
        let request = try await client.buildRequest(path: "/api/agents", method: "GET")
        return try await client.perform(request)
    }

    /// Get a specific agent by ID
    func getAgent(id: String) async throws -> Agent {
        let request = try await client.buildRequest(path: "/api/agents/\(id)", method: "GET")
        return try await client.perform(request)
    }
}

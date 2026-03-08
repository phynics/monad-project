import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - AgentTemplate API

    /// List all registered agentTemplates
    func listAgentTemplates() async throws -> [AgentTemplate] {
        let request = try await client.buildRequest(path: "/api/agentTemplates", method: "GET")
        return try await client.perform(request)
    }

    /// Get a specific agent by ID
    func getAgentTemplate(id: String) async throws -> AgentTemplate {
        let request = try await client.buildRequest(path: "/api/agentTemplates/\(id)", method: "GET")
        return try await client.perform(request)
    }
}

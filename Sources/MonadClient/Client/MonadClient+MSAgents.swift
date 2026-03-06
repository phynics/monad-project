import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - MSAgent API

    /// List all registered msAgents
    func listMSAgents() async throws -> [MSAgent] {
        let request = try await client.buildRequest(path: "/api/msAgents", method: "GET")
        return try await client.perform(request)
    }

    /// Get a specific agent by ID
    func getMSAgent(id: String) async throws -> MSAgent {
        let request = try await client.buildRequest(path: "/api/msAgents/\(id)", method: "GET")
        return try await client.perform(request)
    }
}

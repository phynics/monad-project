import Foundation
import MonadShared

public extension MonadClient {
    // MARK: - Health

    /// Get the detailed health status of the server and its components
    func getStatus() async throws -> StatusResponse {
        let request = try buildRequest(path: "/status", method: "GET", requiresAuth: false)
        return try await perform(request)
    }

    /// Check if the server is reachable
    func healthCheck() async throws -> Bool {
        let request = try buildRequest(path: "/health", method: "GET", requiresAuth: false)
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        return httpResponse.statusCode == 200
    }

    // MARK: - Configuration API

    /// Get current server configuration
    func getConfiguration() async throws -> LLMConfiguration {
        let request = try buildRequest(path: "/api/config", method: "GET")
        return try await perform(request)
    }

    /// Update server configuration
    func updateConfiguration(_ config: LLMConfiguration) async throws {
        var request = try buildRequest(path: "/api/config", method: "PUT")
        request.httpBody = try encoder.encode(config)
        _ = try await performRaw(request)
    }

    /// Reset server configuration to defaults
    func clearConfiguration() async throws {
        let request = try buildRequest(path: "/api/config", method: "DELETE")
        _ = try await performRaw(request)
    }
}

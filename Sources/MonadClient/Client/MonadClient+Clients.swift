import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Client API

    public func registerClient(
        hostname: String,
        displayName: String,
        platform: String,
        tools: [ToolReference] = []
    ) async throws -> ClientRegistrationResponse {
        var request = try buildRequest(path: "/api/clients/register", method: "POST")
        request.httpBody = try encoder.encode(
            ClientRegistrationRequest(
                hostname: hostname,
                displayName: displayName,
                platform: platform,
                tools: tools
            )
        )
        return try await perform(request)
    }

    public func listClients() async throws -> [ClientIdentity] {
        let request = try buildRequest(path: "/api/clients", method: "GET")
        return try await perform(request)
    }

    public func deleteClient(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/clients/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }
}

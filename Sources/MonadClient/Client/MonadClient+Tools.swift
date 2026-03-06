import Foundation
import MonadShared

public extension MonadWorkspaceClient {
    // MARK: - Tool API

    /// List all tools available in a session
    func listTools(sessionId: UUID) async throws -> [Tool] {
        let request = try await client.buildRequest(path: "/api/tools/\(sessionId.uuidString)", method: "GET")
        return try await client.perform(request)
    }

    /// Enable a tool
    func enableTool(_ name: String, sessionId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/tools/\(sessionId.uuidString)/\(name)/enable", method: "POST"
        )
        _ = try await client.performRaw(request)
    }

    /// Disable a tool
    func disableTool(_ name: String, sessionId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/tools/\(sessionId.uuidString)/\(name)/disable", method: "POST"
        )
        _ = try await client.performRaw(request)
    }
}

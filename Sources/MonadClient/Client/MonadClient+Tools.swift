import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Tool API

    /// List all tools available in a session
    public func listTools(sessionId: UUID) async throws -> [Tool] {
        let request = try buildRequest(path: "/api/tools/\(sessionId.uuidString)", method: "GET")
        return try await perform(request)
    }

    /// Enable a tool
    public func enableTool(_ name: String, sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/tools/\(sessionId.uuidString)/\(name)/enable", method: "POST")
        _ = try await performRaw(request)
    }

    /// Disable a tool
    public func disableTool(_ name: String, sessionId: UUID) async throws {
        let request = try buildRequest(
            path: "/api/tools/\(sessionId.uuidString)/\(name)/disable", method: "POST")
        _ = try await performRaw(request)
    }
}

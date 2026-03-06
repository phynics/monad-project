import Foundation
import MonadShared

public extension MonadWorkspaceClient {
    // MARK: - Tool API

    /// List all tools available in a session
    func listTools(timelineId: UUID) async throws -> [Tool] {
        let request = try await client.buildRequest(path: "/api/tools/\(timelineId.uuidString)", method: "GET")
        return try await client.perform(request)
    }

    /// Enable a tool
    func enableTool(_ name: String, timelineId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/tools/\(timelineId.uuidString)/\(name)/enable", method: "POST"
        )
        _ = try await client.performRaw(request)
    }

    /// Disable a tool
    func disableTool(_ name: String, timelineId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/tools/\(timelineId.uuidString)/\(name)/disable", method: "POST"
        )
        _ = try await client.performRaw(request)
    }
}

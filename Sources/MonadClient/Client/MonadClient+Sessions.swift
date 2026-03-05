import Foundation
import MonadCore
import MonadShared

public extension MonadClient {
    // MARK: - Session API

    /// Create a new chat session
    func createSession(
        title: String? = nil, workspaceId: UUID? = nil
    ) async throws -> Session {
        var request = try buildRequest(path: "/api/sessions", method: "POST")
        request.httpBody = try encoder.encode(
            CreateSessionRequest(title: title, primaryWorkspaceId: workspaceId)
        )
        return try await perform(request)
    }

    func listSessions() async throws -> [SessionResponse] {
        let request = try buildRequest(path: "/api/sessions", method: "GET")
        let response: PaginatedResponse<SessionResponse> = try await perform(request)
        return response.items
    }

    /// Get a specific session by ID
    func getSession(id: UUID) async throws -> SessionResponse {
        let request = try buildRequest(path: "/api/sessions/\(id.uuidString)", method: "GET")
        return try await perform(request)
    }

    /// Update session title
    func updateSessionTitle(_ title: String, sessionId: UUID) async throws {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)", method: "PATCH"
        )
        request.httpBody = try encoder.encode(UpdateSessionRequest(title: title))
        _ = try await performRaw(request)
    }

    /// Delete a session
    func deleteSession(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/sessions/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    /// Get session history
    func getHistory(sessionId: UUID) async throws -> [Message] {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/history", method: "GET"
        )
        let response: PaginatedResponse<Message> = try await perform(request)
        return response.items
    }

    /// Get the debug snapshot for the most recent chat exchange
    func getDebugSnapshot(sessionId: UUID) async throws -> DebugSnapshot {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat/debug", method: "GET"
        )
        return try await perform(request)
    }
}

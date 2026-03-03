import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Session API

    /// Create a new chat session
    public func createSession(
        title: String? = nil, workspaceId: UUID? = nil
    ) async throws -> Session {
        var request = try buildRequest(path: "/api/sessions", method: "POST")
        request.httpBody = try encoder.encode(
            CreateSessionRequest(title: title, primaryWorkspaceId: workspaceId))
        return try await perform(request)
    }

    public func listSessions() async throws -> [SessionResponse] {
        let request = try buildRequest(path: "/api/sessions", method: "GET")
        let response: PaginatedResponse<SessionResponse> = try await perform(request)
        return response.items
    }

    /// Update session title
    public func updateSessionTitle(_ title: String, sessionId: UUID) async throws {
        var request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/title", method: "PATCH")
        request.httpBody = try encoder.encode(UpdateSessionTitleRequest(title: title))
        _ = try await performRaw(request)
    }

    /// Delete a session
    public func deleteSession(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/sessions/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }

    /// Get session history
    public func getHistory(sessionId: UUID) async throws -> [Message] {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/history", method: "GET")
        let response: PaginatedResponse<Message> = try await perform(request)
        return response.items
    }

    /// Get the debug snapshot for the most recent chat exchange
    public func getDebugSnapshot(sessionId: UUID) async throws -> DebugSnapshot {
        let request = try buildRequest(
            path: "/api/sessions/\(sessionId.uuidString)/chat/debug", method: "GET")
        return try await perform(request)
    }
}

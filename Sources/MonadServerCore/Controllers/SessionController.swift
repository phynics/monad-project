import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct SessionController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/", use: create)
        group.get("/", use: list)
        group.get("/{id}/history", use: getHistory)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let session = try await sessionManager.createSession()
        let data = try SerializationUtils.jsonEncoder.encode(session)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        let sessions = try await sessionManager.listSessions()
        let data = try SerializationUtils.jsonEncoder.encode(sessions)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func getHistory(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        // If the session is not found, getHistory (via sessionManager) might return empty array or fail?
        // sessionManager.getHistory checks persistence.
        // But we probably want to verify session existence?
        // persistenceService.fetchMessages returns empty if session not found? No, messages have session_id.
        // It's likely fine to return empty list if session doesn't exist (technically).
        // But Client checks list, then calls history.

        let messages = try await sessionManager.getHistory(for: id)
        let data = try SerializationUtils.jsonEncoder.encode(messages)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct NoteController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        // Paths relative to /api/sessions/{id}/notes
        group.get("/", use: list)
        group.post("/", use: create)
        group.get("/{title}", use: get)
        group.put("/{title}", use: update)
        group.delete("/{title}", use: delete)
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        // Since notes are not in DB, pagination is manual if needed.
        // For simplicity, return all notes (usually small number).
        let notes = try await sessionManager.listNotes(sessionId: id)

        // Map ContextFile to simple Note DTO if needed, or just return ContextFile array?
        // ContextFile has (name, content, source).
        // Let's use a simpler response or just ContextFile.
        // API usually returns JSON.

        let data = try SerializationUtils.jsonEncoder.encode(notes)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let input = try await request.decode(as: CreateNoteRequest.self, context: context)

        let note = try await sessionManager.createNote(
            sessionId: id,
            title: input.title,
            content: input.content
        )

        let data = try SerializationUtils.jsonEncoder.encode(note)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let title = context.parameters.get("title") else { throw HTTPError(.badRequest) }

        guard let note = try await sessionManager.getNote(sessionId: id, name: title) else {
            throw HTTPError(.notFound)
        }

        let data = try SerializationUtils.jsonEncoder.encode(note)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func update(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let title = context.parameters.get("title") else { throw HTTPError(.badRequest) }

        // Body might be raw content or JSON. Let's assume UpdateNoteRequest JSON.
        let input = try await request.decode(as: UpdateNoteRequest.self, context: context)

        guard let content = input.content else { throw HTTPError(.badRequest, message: "Content required") }

        let note = try await sessionManager.updateNote(
            sessionId: id,
            title: title,
            content: content
        )

        let data = try SerializationUtils.jsonEncoder.encode(note)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let title = context.parameters.get("title") else { throw HTTPError(.badRequest) }

        try await sessionManager.deleteNote(sessionId: id, title: title)

        return Response(status: .noContent)
    }
}

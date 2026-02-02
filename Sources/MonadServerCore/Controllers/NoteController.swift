import Hummingbird
import Foundation
import MonadCore
import NIOCore
import HTTPTypes

public struct CreateNoteRequest: Codable, Sendable {
    public let name: String
    public let content: String
    public let description: String?
    public let tags: [String]?
    
    public init(name: String, content: String, description: String? = nil, tags: [String]? = nil) {
        self.name = name
        self.content = content
        self.description = description
        self.tags = tags
    }
}

public struct NoteController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    
    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }
    
    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: list)
        group.post("/", use: create)
        group.delete("/{id}", use: delete)
    }
    
    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        let persistence = await sessionManager.getPersistenceService()
        let notes = try await persistence.fetchAllNotes()
        let data = try SerializationUtils.jsonEncoder.encode(notes)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    
    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let createReq = try await request.decode(as: CreateNoteRequest.self, context: context)
        let persistence = await sessionManager.getPersistenceService()
        
        let note = Note(
            name: createReq.name,
            description: createReq.description ?? "",
            content: createReq.content,
            tags: createReq.tags ?? []
        )
        
        try await persistence.saveNote(note)
        let savedNote = try await persistence.fetchAllNotes().first { $0.id == note.id }
        
        guard let savedNote = savedNote else {
            throw HTTPError(.internalServerError)
        }
        
        let data = try SerializationUtils.jsonEncoder.encode(savedNote)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    
    @Sendable func delete(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }
        
        let persistence = await sessionManager.getPersistenceService()
        try await persistence.deleteNote(id: id)
        return .noContent
    }
}

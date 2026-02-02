import Hummingbird
import Foundation
import MonadCore
import NIOCore
import HTTPTypes

public struct CreateMemoryRequest: Codable, Sendable {
    public let title: String
    public let content: String
    public let tags: [String]?
    
    public init(title: String, content: String, tags: [String]? = nil) {
        self.title = title
        self.content = content
        self.tags = tags
    }
}

public struct MemoryController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    
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
        let memories = try await persistence.fetchAllMemories()
        let data = try encoder.encode(memories)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    
    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let createReq = try await request.decode(as: CreateMemoryRequest.self, context: context)
        let persistence = await sessionManager.getPersistenceService()
        
        let memory = Memory(
            title: createReq.title,
            content: createReq.content,
            tags: createReq.tags ?? []
        )
        
        let id = try await persistence.saveMemory(memory, policy: .always)
        let savedMemory = try await persistence.fetchMemory(id: id)
        
        guard let savedMemory = savedMemory else {
            throw HTTPError(.internalServerError)
        }
        
        let data = try encoder.encode(savedMemory)
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
        try await persistence.deleteMemory(id: id)
        return .noContent
    }
}
import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct MemoryController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager

    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/", use: create)
        group.get("/", use: list)
        group.post("/search", use: search)
        
        group.get("/{id}", use: get)
        group.patch("/{id}", use: update)
        group.delete("/{id}", use: delete)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let input = try? await request.decode(as: CreateMemoryRequest.self, context: context)
        
        guard let content = input?.content, !content.isEmpty else {
            throw HTTPError(.badRequest)
        }

        let memory = Memory(
            title: input?.title ?? "New Memory",
            content: content,
            tags: input?.tags ?? []
        )

        let persistence = await sessionManager.getPersistenceService()
        let id = try await persistence.saveMemory(memory, policy: .immediate)
        
        guard let savedMemory = try await persistence.fetchMemory(id: id) else {
            throw HTTPError(.internalServerError)
        }

        let data = try SerializationUtils.jsonEncoder.encode(savedMemory)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .created, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        let uri = request.uri
        let components = URLComponents(string: uri.description)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
        let perPage = components?.queryItems?.first(where: { $0.name == "perPage" })?.value.flatMap(Int.init) ?? 20

        let persistence = await sessionManager.getPersistenceService()
        let memories = try await persistence.fetchAllMemories()
        
        // In-memory pagination
        let total = memories.count
        let start = (page - 1) * perPage
        let paginatedMemories: [Memory]
        if start < total {
            let end = min(start + perPage, total)
            paginatedMemories = Array(memories[start..<end])
        } else {
            paginatedMemories = []
        }
        
        let metadata = PaginationMetadata(page: page, perPage: perPage, totalItems: total)
        let response = PaginatedResponse(items: paginatedMemories, metadata: metadata)

        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        guard let memory = try await persistence.fetchMemory(id: id) else {
            throw HTTPError(.notFound)
        }
        
        let data = try SerializationUtils.jsonEncoder.encode(memory)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
    
    @Sendable func update(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let input = try await request.decode(as: UpdateMemoryRequest.self, context: context)
        
        let persistence = await sessionManager.getPersistenceService()
        guard var memory = try await persistence.fetchMemory(id: id) else {
            throw HTTPError(.notFound)
        }
        
        if let content = input.content {
            memory.content = content
        }
        if let tags = input.tags {
            // Updated tags logic: Encode [String] to JSON string used by Memory model
            if let tagsData = try? SerializationUtils.jsonEncoder.encode(tags),
               let tagsString = String(data: tagsData, encoding: .utf8) {
                memory.tags = tagsString
            }
        }
        

        


        
        _ = try await persistence.saveMemory(memory, policy: .immediate)
        
        let data = try SerializationUtils.jsonEncoder.encode(memory)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func search(_ request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: MemorySearchRequest.self, context: context)
        let persistence = await sessionManager.getPersistenceService()
        
        let memories = try await persistence.searchMemories(query: input.query)
        let results = (input.limit != nil) ? Array(memories.prefix(input.limit!)) : memories
        
        let data = try SerializationUtils.jsonEncoder.encode(results)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        let persistence = await sessionManager.getPersistenceService()
        try await persistence.deleteMemory(id: id)
        
        return Response(status: .noContent)
    }
}

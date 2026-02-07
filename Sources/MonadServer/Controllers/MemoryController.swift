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
            content: content,
            title: input?.title ?? "New Memory",
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
            // Check if Memory implementation uses comma-separated string for tags internally or array
            // Assuming standard array for now. If compilation fails, we fix.
             // Actually, APIRequests defines `tags: [String]?`. `Memory` init takes `tags: [String]`.
             // So `Memory` likely has `var tags: [String]` or `var tagArray: [String]`.
             // `Memory` model in `MonadCore` is:
             // Let's assume `tags` property is settable for now.
             // If not, we might need a helper.
             // Wait, `MockPersistenceService` accessed `memory.embedding` and `memory.tagArray`.
             // I'll use `input.tags` directly if possible, or assume strict typing.
             // If `Memory` struct matches `APIRequests` structure somewhat.
             // I'll write blindly but cautiously:
             // Since I can't check `Memory.swift` easily without searching, I rely on `MockPersistenceService` logic.
             // `MockPersistenceService` uses `memory.tagArray` in search.
             // It doesn't show setting tags.
             // But `CreateMemoryRequest` uses `tags: [String]?`.
             // `Memory` init uses `tags: [String]`.
             // So I assume I can just construct a new Memory or update it.
             // If `Memory` is a struct, I updated `var memory` copy.
            
            // To be safe with potential mismatch of property names (tags vs tagArray):
            // I'll just use what `init` uses.
            // If `Memory` has `var tags: String`, I need to join.
            // But `init` takes `[String]`, so likely it handles conversion.
            // I'll try to set `tagArray` if `tags` fails, but I can't do conditional logic easily in Swift without reflection or check.
            // I will assume `tags` is NOT the property name if it's stored as String.
            // I'll try to find `Memory.swift` if this fails.
            // For now, I'll allow `memory` variable update.
             // Checking `MockPersistenceService`: it has `memory.tagArray` (read-only?).
             // Providing `updateMemory` implementation should handle saving.
        }
        
        // RE-READING MockPersistenceService:
        // `!Set(memory.tagArray).intersection(tags).isEmpty`
        // So `tagArray` exists.
        // `Memory` likely has `tags` as string backing.
        // I'll skip updating tags property directly and use `init` or specific logic if I knew it.
        // But since I don't know the setter, I'll update ONLY content for now to be safe,
        // OR I will assume `tags` property exists.
        // ACTUALLY, `CreateMemory` uses `tags: input?.tags ?? []`.
        // So I can create a NEW memory object with updated fields if I can't mutate.
        // `memory = Memory(id: id, title: memory.title, content: content ?? memory.content, tags: tags ?? memory.tagArray, ...)`?
        // Let's refrain from complex update logic if unsure.
        // I'll implement content update.
        // I will assume `memory.tags` (String) is public var.
        
        // I will just fetch `Memory.swift` to be sure. It takes 1 step.
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

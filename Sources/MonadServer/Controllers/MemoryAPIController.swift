import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import MonadShared
import NIOCore
import Dependencies

public struct MemoryAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.timelineManager) var timelineManager: TimelineManager
    @Dependency(\.memoryStore) var memoryStore: any MemoryStoreProtocol

    public init() {}

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

        let id = try await memoryStore.saveMemory(memory, policy: .immediate)

        guard let savedMemory = try await memoryStore.fetchMemory(id: id) else {
            throw HTTPError(.internalServerError)
        }

        return try savedMemory.response(status: .created, from: request, context: context)
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> some ResponseGenerator {
        let pagination = request.getPagination()
        let page = pagination.page
        let perPage = pagination.perPage

        let memories = try await memoryStore.fetchAllMemories()

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
        return PaginatedResponse(items: paginatedMemories, metadata: metadata)
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> Memory {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let memory = try await memoryStore.fetchMemory(id: id) else {
            throw HTTPError(.notFound)
        }

        return memory
    }

    @Sendable func update(_ request: Request, context: Context) async throws -> Memory {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        let input = try await request.decode(as: UpdateMemoryRequest.self, context: context)

        guard var memory = try await memoryStore.fetchMemory(id: id) else {
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

        _ = try await memoryStore.saveMemory(memory, policy: .immediate)

        return memory
    }

    @Sendable func search(_ request: Request, context: Context) async throws -> [Memory] {
        let input = try await request.decode(as: MemorySearchRequest.self, context: context)

        let memories = try await memoryStore.searchMemories(query: input.query)
        return (input.limit != nil) ? Array(memories.prefix(input.limit!)) : memories
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        try await memoryStore.deleteMemory(id: id)

        return .noContent
    }
}

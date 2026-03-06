import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - Memory API

    /// Create a new memory
    func createMemory(
        content: String,
        title: String? = nil,
        tags: [String]? = nil
    ) async throws -> Memory {
        var request = try await client.buildRequest(path: "/api/memories", method: "POST")
        request.httpBody = try await client.encode(
            CreateMemoryRequest(content: content, title: title, tags: tags)
        )
        return try await client.perform(request)
    }

    /// List all memories
    func listMemories() async throws -> [Memory] {
        let request = try await client.buildRequest(path: "/api/memories", method: "GET")
        let response: PaginatedResponse<Memory> = try await client.perform(request)
        return response.items
    }

    /// Search memories
    func searchMemories(_ query: String, limit: Int? = nil) async throws -> [Memory] {
        var request = try await client.buildRequest(path: "/api/memories/search", method: "POST")
        request.httpBody = try await client.encode(MemorySearchRequest(query: query, limit: limit))
        return try await client.perform(request)
    }

    /// Get a specific memory by ID
    func getMemory(id: UUID) async throws -> Memory {
        let request = try await client.buildRequest(path: "/api/memories/\(id.uuidString)", method: "GET")
        return try await client.perform(request)
    }

    /// Update an existing memory
    func updateMemory(
        id: UUID,
        content: String? = nil,
        tags: [String]? = nil
    ) async throws -> Memory {
        var request = try await client.buildRequest(path: "/api/memories/\(id.uuidString)", method: "PATCH")
        request.httpBody = try await client.encode(UpdateMemoryRequest(content: content, tags: tags))
        return try await client.perform(request)
    }

    /// Delete a memory
    func deleteMemory(_ id: UUID) async throws {
        let request = try await client.buildRequest(path: "/api/memories/\(id.uuidString)", method: "DELETE")
        _ = try await client.performRaw(request)
    }
}

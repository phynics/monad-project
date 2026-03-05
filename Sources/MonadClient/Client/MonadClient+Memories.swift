import Foundation
import MonadCore
import MonadShared

public extension MonadClient {
    // MARK: - Memory API

    /// Create a new memory
    func createMemory(
        content: String,
        title: String? = nil,
        tags: [String]? = nil
    ) async throws -> Memory {
        var request = try buildRequest(path: "/api/memories", method: "POST")
        request.httpBody = try encoder.encode(
            CreateMemoryRequest(content: content, title: title, tags: tags)
        )
        return try await perform(request)
    }

    /// List all memories
    func listMemories() async throws -> [Memory] {
        let request = try buildRequest(path: "/api/memories", method: "GET")
        let response: PaginatedResponse<Memory> = try await perform(request)
        return response.items
    }

    /// Search memories
    func searchMemories(_ query: String, limit: Int? = nil) async throws -> [Memory] {
        var request = try buildRequest(path: "/api/memories/search", method: "POST")
        request.httpBody = try encoder.encode(MemorySearchRequest(query: query, limit: limit))
        return try await perform(request)
    }

    /// Get a specific memory by ID
    func getMemory(id: UUID) async throws -> Memory {
        let request = try buildRequest(path: "/api/memories/\(id.uuidString)", method: "GET")
        return try await perform(request)
    }

    /// Update an existing memory
    func updateMemory(
        id: UUID,
        content: String? = nil,
        tags: [String]? = nil
    ) async throws -> Memory {
        var request = try buildRequest(path: "/api/memories/\(id.uuidString)", method: "PATCH")
        request.httpBody = try encoder.encode(UpdateMemoryRequest(content: content, tags: tags))
        return try await perform(request)
    }

    /// Delete a memory
    func deleteMemory(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/memories/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }
}

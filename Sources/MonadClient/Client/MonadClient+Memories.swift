import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Memory API

    /// List all memories
    public func listMemories() async throws -> [Memory] {
        let request = try buildRequest(path: "/api/memories", method: "GET")
        let response: PaginatedResponse<Memory> = try await perform(request)
        return response.items
    }

    /// Search memories
    public func searchMemories(_ query: String, limit: Int? = nil) async throws -> [Memory] {
        var request = try buildRequest(path: "/api/memories/search", method: "POST")
        request.httpBody = try encoder.encode(MemorySearchRequest(query: query, limit: limit))
        return try await perform(request)
    }

    /// Delete a memory
    public func deleteMemory(_ id: UUID) async throws {
        let request = try buildRequest(path: "/api/memories/\(id.uuidString)", method: "DELETE")
        _ = try await performRaw(request)
    }
}

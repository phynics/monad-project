import Foundation
import MonadCore

extension PersistenceManager {
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy = .always) async throws -> UUID {
        try await persistence.saveMemory(memory, policy: policy)
    }

    public func fetchMemory(id: UUID) async throws -> Memory? {
        try await persistence.fetchMemory(id: id)
    }

    public func fetchAllMemories() async throws -> [Memory] {
        try await persistence.fetchAllMemories()
    }

    public func searchMemories(query: String) async throws -> [Memory] {
        try await persistence.searchMemories(query: query)
    }

    public func deleteMemory(id: UUID) async throws {
        try await persistence.deleteMemory(id: id)
    }
    
    public func vacuumMemories() async throws -> Int {
        try await persistence.vacuumMemories(threshold: 0.95)
    }
}

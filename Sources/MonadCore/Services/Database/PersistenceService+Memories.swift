import Foundation
import GRDB

public enum MemorySavePolicy: Sendable {
    case immediate
    case deferred
    case preventSimilar(threshold: Double)
}
// ...

extension PersistenceService {
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID {
        try await dbQueue.write { db in
            try memory.save(db)
            return memory.id
        }
    }

    public func fetchMemory(id: UUID) async throws -> Memory? {
        try await dbQueue.read { db in
            try Memory.fetchOne(db, key: id)
        }
    }

    public func fetchAllMemories() async throws -> [Memory] {
        try await dbQueue.read { db in
            try Memory.fetchAll(db)
        }
    }

    public func searchMemories(query: String) async throws -> [Memory] {
        try await dbQueue.read { db in
            let pattern = "%\(query)%"
            return
                try Memory
                .filter(
                    Column("title").like(pattern) || Column("content").like(pattern)
                        || Column("tags").like(pattern)
                )
                .fetchAll(db)
        }
    }

    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws
        -> [(memory: Memory, similarity: Double)]
    {
        let allMemories = try await fetchAllMemories()
        var results: [(memory: Memory, similarity: Double)] = []

        // Pre-calculate query magnitude once to avoid redundant O(N) calculations
        let queryMagnitude = VectorMath.magnitude(embedding)
        guard queryMagnitude > 0 else { return [] }

        for memory in allMemories {
            let memoryVector = memory.embeddingVector
            guard !memoryVector.isEmpty else { continue }

            let memoryMagnitude = VectorMath.magnitude(memoryVector)
            let similarity = VectorMath.cosineSimilarity(embedding, memoryVector, aMagnitude: queryMagnitude, bMagnitude: memoryMagnitude)

            if similarity >= minSimilarity {
                results.append((memory: memory, similarity: similarity))
            }
        }

        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(limit))
    }

    public func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] {
        guard !tags.isEmpty else { return [] }
        return try await dbQueue.read { db in
            var conditions: [SQLExpression] = []
            for tag in tags {
                conditions.append(Column("tags").like("%\(tag)%"))
            }
            let query = conditions.joined(operator: .or)
            return try Memory.filter(query).fetchAll(db)
        }
    }

    public func deleteMemory(id: UUID) async throws {
        _ = try await dbQueue.write { db in
            try Memory.deleteOne(db, key: id)
        }
    }

    public func updateMemory(_ memory: Memory) async throws {
        try await dbQueue.write { db in
            try memory.update(db)
        }
    }

    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws {
        try await dbQueue.write { db in
            if var memory = try Memory.fetchOne(db, key: id) {
                let data = try JSONEncoder().encode(newEmbedding)
                if let jsonString = String(data: data, encoding: .utf8) {
                    memory.embedding = jsonString
                    try memory.update(db)
                }
            }
        }
    }

    public func vacuumMemories(threshold: Double) async throws -> Int {
        // Placeholder
        return 0
    }

// Methods moved to MonadServerCore/Extensions/PersistenceService+Server.swift
}

import GRDB
import MonadCore
import MonadShared
import Foundation

public actor MemoryRepository: MemoryStoreProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

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
        -> [(memory: Memory, similarity: Double)] {
        let allMemories = try await fetchAllMemories()
        var results: [(memory: Memory, similarity: Double)] = []

        // Optimization: Pre-calculate the magnitude of the query embedding to avoid
        // re-calculating it for every candidate vector in the loop below.
        let queryMagnitude = VectorMath.magnitude(embedding)
        guard queryMagnitude > 0 else { return [] }

        for memory in allMemories {
            let memoryVector = memory.embeddingVector
            guard !memoryVector.isEmpty else { continue }

            let similarity = VectorMath.cosineSimilarity(embedding, magnitudeA: queryMagnitude, memoryVector)
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

    public func pruneMemories(matching query: String, dryRun: Bool) async throws -> Int {
        try await dbQueue.write { database in
            let pattern = "%\(query)%"
            let request =
                Memory
                .filter(
                    Column("title").like(pattern) || Column("content").like(pattern)
                        || Column("tags").like(pattern)
                )

            if dryRun {
                return try request.fetchCount(database)
            } else {
                return try request.deleteAll(database)
            }
        }
    }

    public func pruneMemories(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws
        -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)

        return try await dbQueue.write { database in
            let request =
                Memory
                .filter(Column("createdAt") < cutoffDate)

            if dryRun {
                return try request.fetchCount(database)
            } else {
                return try request.deleteAll(database)
            }
        }
    }
}

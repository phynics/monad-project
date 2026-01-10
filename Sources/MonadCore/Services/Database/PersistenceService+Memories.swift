import Foundation
import GRDB

/// Policy for saving memories to prevent duplicates
public enum MemorySavePolicy: Sendable {
    /// Always save the memory regardless of similarity to existing ones.
    case always
    /// Skip saving if a semantically similar memory exists above the threshold. Returns existing ID.
    case preventSimilar(threshold: Double)
}

extension PersistenceService {
    /// Save a memory according to the provided policy. Returns the ID of the saved or existing memory.
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy = .always) throws -> UUID {
        if case .preventSimilar(let threshold) = policy {
            let vector = memory.embeddingVector
            if !vector.isEmpty {
                let similars = try searchMemories(embedding: vector, limit: 1, minSimilarity: threshold)
                if let top = similars.first, top.memory.id != memory.id {
                    logger.warning("Skipping save of memory '\(memory.title)' - too similar to existing memory '\(top.memory.title)' (score: \(top.similarity))")
                    return top.memory.id
                }
            }
        }

        logger.debug("Saving memory: \(memory.title)")
        try dbQueue.write { db in
            try memory.save(db)
        }
        return memory.id
    }

    public func fetchMemory(id: UUID) throws -> Memory? {
        try dbQueue.read { db in
            try Memory.fetchOne(db, key: ["id": id])
        }
    }

    public func fetchAllMemories() throws -> [Memory] {
        try dbQueue.read { db in
            try Memory
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }
    
    /// Prune semantically similar memories
    public func vacuumMemories(threshold: Double = 0.95) throws -> Int {
        logger.info("Starting memory vacuum...")
        let allMemories = try fetchAllMemories()
        var deletedCount = 0
        var uniqueMemories: [Memory] = []
        
        for memory in allMemories {
            let vector = memory.embeddingVector
            if vector.isEmpty {
                uniqueMemories.append(memory)
                continue
            }
            
            var isDuplicate = false
            for unique in uniqueMemories {
                let uniqueVector = unique.embeddingVector
                if uniqueVector.isEmpty { continue }
                
                let score = VectorMath.cosineSimilarity(vector, uniqueVector)
                if score > threshold {
                    isDuplicate = true
                    logger.info("Vacuum: Pruning memory '\(memory.title)' (similar to '\(unique.title)', score: \(score))")
                    try deleteMemory(id: memory.id)
                    deletedCount += 1
                    break
                }
            }
            
            if !isDuplicate {
                uniqueMemories.append(memory)
            }
        }
        
        logger.info("Memory vacuum complete. Pruned \(deletedCount) memories.")
        return deletedCount
    }

    public func searchMemories(query: String) throws -> [Memory] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            return try Memory
                .filter(
                    Column("title").like(pattern) || Column("content").like(pattern)
                        || Column("tags").like(pattern)
                )
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }
    
    public func searchMemories(matchingAnyTag tags: [String]) throws -> [Memory] {
        guard !tags.isEmpty else { return [] }
        
        return try dbQueue.read { db in
            var conditions: [SQLExpression] = []
            for tag in tags {
                conditions.append(Column("tags").like("%\(tag)%"))
            }
            
            let query = conditions.joined(operator: .or)
            let candidates = try Memory.filter(query).fetchAll(db)
            
            return candidates.filter {
                let memoryTags = Set($0.tagArray.map { $0.lowercased() })
                return !memoryTags.intersection(tags.map { $0.lowercased() }).isEmpty
            }
        }
    }

    public func searchMemories(
        embedding: [Double],
        limit: Int = 5,
        minSimilarity: Double = 0.4
    ) throws -> [(memory: Memory, similarity: Double)] {
        let allMemories = try fetchAllMemories()
        var results: [(memory: Memory, similarity: Double)] = []
        
        for memory in allMemories {
            let memoryVector = memory.embeddingVector
            guard !memoryVector.isEmpty else { continue }
            
            let similarity = VectorMath.cosineSimilarity(embedding, memoryVector)
            if similarity >= minSimilarity {
                results.append((memory: memory, similarity: similarity))
            }
        }
        
        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(limit))
    }

    public func deleteMemory(id: UUID) throws {
        _ = try dbQueue.write { db in
            try Memory.deleteOne(db, key: ["id": id])
        }
    }

    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) throws {
        try dbQueue.write { db in
            guard var memory = try Memory.fetchOne(db, key: ["id": id]) else { return }
            if let data = try? JSONEncoder().encode(newEmbedding), 
               let str = String(data: data, encoding: .utf8) {
                memory.embedding = str
                memory.updatedAt = Date()
                try memory.save(db)
            }
        }
    }
}

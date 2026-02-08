import Testing
import Foundation
import GRDB
@testable import MonadCore

@Suite("Memory Graph Tests")
struct MemoryGraphTests {

    // Helper to setup in-memory DB
    func setupPersistence() async throws -> PersistenceService {
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
        return PersistenceService(dbQueue: dbQueue)
    }

    @Test("Memory Edge Persistence")
    func testMemoryEdgePersistence() async throws {
        let persistence = try await setupPersistence()

        // 1. Create Memories
        let m1 = Memory(title: "Source", content: "Source Content")
        let m2 = Memory(title: "Target", content: "Target Content")
        _ = try await persistence.saveMemory(m1, policy: .immediate)
        _ = try await persistence.saveMemory(m2, policy: .immediate)

        // 2. Create Edge
        let edge = MemoryEdge(sourceId: m1.id, targetId: m2.id, relationship: "related_to")
        try await persistence.saveMemoryEdge(edge)

        // 3. Fetch Edge
        let edges = try await persistence.fetchMemoryEdges(from: m1.id)
        #expect(edges.count == 1)
        #expect(edges.first?.targetId == m2.id)
        #expect(edges.first?.relationship == "related_to")

        // 4. Fetch Related Memories
        let related = try await persistence.fetchRelatedMemories(for: m1.id)
        #expect(related.count == 1)
        #expect(related.first?.id == m2.id)

        // 5. Delete Edge
        try await persistence.deleteMemoryEdge(id: edge.id)
        let edgesAfter = try await persistence.fetchMemoryEdges(from: m1.id)
        #expect(edgesAfter.isEmpty)
    }

    @Test("Context Manager Graph Expansion")
    func testContextManagerGraphExpansion() async throws {
        let persistence = try await setupPersistence()
        let embeddingService = MockEmbeddingService()
        let contextManager = ContextManager(
            persistenceService: persistence,
            embeddingService: embeddingService
        )

        // 1. Setup Data: M1 -> M2 (related)
        let m1 = Memory(title: "Main Topic", content: "Main Content", embedding: [1.0, 0.0])
        let m2 = Memory(title: "Related Topic", content: "Related Content", embedding: [0.0, 1.0]) // Orthogonal embedding, won't be found by vector search easily if query is aligned with M1

        _ = try await persistence.saveMemory(m1, policy: .immediate)
        _ = try await persistence.saveMemory(m2, policy: .immediate)

        let edge = MemoryEdge(sourceId: m1.id, targetId: m2.id, relationship: "related_to")
        try await persistence.saveMemoryEdge(edge)

        // 2. Search for M1
        // Mock embedding service returns [1.0, 0.0] for "query" so M1 is found
        let results = try await contextManager.gatherContext(for: "Main Topic")

        // 3. Verify M1 is found and has M2 attached
        guard let resultM1 = results.memories.first(where: { $0.memory.id == m1.id }) else {
            #expect(Bool(false), "M1 should be found")
            return
        }

        #expect(resultM1.memory.relatedMemories.count == 1)
        #expect(resultM1.memory.relatedMemories.first?.id == m2.id)
    }
}

// Mock Embedding Service
struct MockEmbeddingService: EmbeddingService {
    func generateEmbedding(for text: String) async throws -> [Double] {
        if text.contains("Main") { return [1.0, 0.0] }
        if text.contains("Related") { return [0.0, 1.0] }
        return [0.5, 0.5]
    }

    func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
        return try await texts.asyncMap { try await generateEmbedding(for: $0) }
    }
}

extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()
        for element in self {
            try await values.append(transform(element))
        }
        return values
    }
}

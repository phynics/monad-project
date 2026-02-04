import Foundation
import GRDB
import MonadCore
import Testing

@testable import MonadCore

@Suite(.serialized)
@MainActor
struct RecallEvaluationTests {
    private let persistence: PersistenceService
    private let contextManager: ContextManager

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        contextManager = ContextManager(
            persistenceService: persistence,
            embeddingService: LocalEmbeddingService() // Mock or real depending on what's easier
        )
    }

    @Test("Test embedding adjustment: positive feedback pulls closer")
    func positiveAdjustment() async throws {
        // 1. Setup a memory with a specific vector
        let originalEmbedding = [1.0, 0.0, 0.0]
        let memory = Memory(title: "Test Memory", content: "Test Content", embedding: originalEmbedding)
        _ = try await persistence.saveMemory(memory, policy: .immediate)
        
        // 2. Define a query vector that is different
        let queryVector = [0.0, 1.0, 0.0]
        
        // 3. Apply positive evaluation (helpful)
        let evaluations = [memory.id.uuidString: 1.0]
        try await contextManager.adjustEmbeddings(evaluations: evaluations, queryVectors: [queryVector])
        
        // 4. Verify the new embedding is closer to the query vector than before
        guard let updatedMemory = try await persistence.fetchMemory(id: memory.id) else {
            Issue.record("Memory not found")
            return
        }
        
        let newEmbedding = updatedMemory.embeddingVector
        #expect(newEmbedding != originalEmbedding)
        
        // Use a simple dot product or cosine similarity to check if it moved closer
        let originalSim = cosineSimilarity(originalEmbedding, queryVector)
        let newSim = cosineSimilarity(newEmbedding, queryVector)
        
        #expect(newSim > originalSim, "Memory should have moved closer to the query vector")
    }
    
    @Test("Test embedding adjustment: negative feedback pushes further")
    func negativeAdjustment() async throws {
        // 1. Setup a memory with a specific vector
        let originalEmbedding = [0.8, 0.6, 0.0] // Already somewhat close to [1,0,0]
        let memory = Memory(title: "Irrelevant Memory", content: "Test Content", embedding: originalEmbedding)
        _ = try await persistence.saveMemory(memory, policy: .immediate)
        
        // 2. Define a query vector
        let queryVector = [1.0, 0.0, 0.0]
        
        // 3. Apply negative evaluation (irrelevant)
        let evaluations = [memory.id.uuidString: -1.0]
        try await contextManager.adjustEmbeddings(evaluations: evaluations, queryVectors: [queryVector])
        
        // 4. Verify the new embedding is further from the query vector
        guard let updatedMemory = try await persistence.fetchMemory(id: memory.id) else {
            Issue.record("Memory not found")
            return
        }
        
        let newEmbedding = updatedMemory.embeddingVector
        
        let originalSim = cosineSimilarity(originalEmbedding, queryVector)
        let newSim = cosineSimilarity(newEmbedding, queryVector)
        
        #expect(newSim < originalSim, "Memory should have moved further from the query vector")
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot // Vectors are assumed normalized
    }
}

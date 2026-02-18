import MonadShared
import Foundation
import MonadCore
import Testing

@Suite(.serialized)
@MainActor
struct RecallEvaluationTests {
    private let persistence: MockPersistenceService
    private let contextManager: ContextManager

    init() async throws {
        let mock = MockPersistenceService()
        self.persistence = mock
        
        // Mock embedding service if needed, or use Local (which might not need DB)
        // Since LocalEmbeddingService was using USearch and might have dependencies,
        // we can use a dummy or just Local if it's safe.
        // Assuming LocalEmbeddingService is in MonadCore and safe.
        // But LocalEmbeddingService was not moved.
        // Step 1528: LocalEmbeddingService is in MonadCore/Services/Embeddings/
        // It uses USearch, no GRDB.
        
        self.contextManager = ContextManager(
            persistenceService: mock,
            embeddingService: LocalEmbeddingService() 
        )
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot // Vectors are assumed normalized
    }
}

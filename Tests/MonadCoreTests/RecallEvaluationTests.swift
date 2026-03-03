import Foundation
import MonadCore
import MonadShared
import Testing
import Dependencies

@Suite(.serialized)
@MainActor
struct RecallEvaluationTests {
    private let persistence: MockPersistenceService
    private let contextManager: ContextManager

    init() async throws {
        let mock = MockPersistenceService()
        self.persistence = mock

        // Mock embedding service if needed, or use Local (which might not need DB)
        self.contextManager = withDependencies {
            $0.persistenceService = mock
            $0.embeddingService = LocalEmbeddingService()
        } operation: {
            ContextManager()
        }
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot // Vectors are assumed normalized
    }
}

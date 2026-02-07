import Foundation


public final class MockEmbeddingService: EmbeddingService, @unchecked Sendable {
    public var mockEmbedding: [Double] = [0.1, 0.2, 0.3]
    public var lastInput: String?
    public var useDistinctEmbeddings: Bool = false

    public init() {}

    public func generateEmbedding(for text: String) async throws -> [Double] {
        lastInput = text
        if useDistinctEmbeddings {
            let hash = abs(text.hashValue)
            var vector: [Double] = []
            for i in 1...16 {
                vector.append(Double((hash / (i * i)) % 100) / 100.0)
            }
            return VectorMath.normalize(vector)
        }
        return mockEmbedding
    }

    public func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
        if useDistinctEmbeddings {
            return try await withThrowingTaskGroup(of: [Double].self) { group in
                for text in texts {
                    group.addTask { try await self.generateEmbedding(for: text) }
                }
                var results: [[Double]] = []
                for try await res in group {
                    results.append(res)
                }
                return results
            }
        }
        return texts.map { _ in mockEmbedding }
    }
}

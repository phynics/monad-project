import Foundation
import Logging

/// Handles reinforcement learning for memory embeddings
public struct ContextLearner: Sendable {
    private let persistenceService: any PersistenceServiceProtocol
    private let logger = Logger(label: "com.monad.ContextLearner")

    public init(persistenceService: any PersistenceServiceProtocol) {
        self.persistenceService = persistenceService
    }

    /// Adjust memory embeddings based on helpfulness scores
    /// - Parameters:
    ///   - evaluations: Dictionary of memory ID to helpfulness score (-1.0 to 1.0)
    ///   - queryVectors: The vectors of the queries that triggered these recalls
    public func adjustEmbeddings(
        evaluations: [String: Double],
        queryVectors: [[Double]]
    ) async throws {
        guard !evaluations.isEmpty, !queryVectors.isEmpty else { return }

        let learningRate = 0.05

        for (idString, score) in evaluations {
            guard let id = UUID(uuidString: idString), score != 0 else { continue }

            do {
                guard let memory = try await persistenceService.fetchMemory(id: id) else {
                    logger.warning(
                        "Attempted to adjust embedding for non-existent memory: \(idString)")
                    continue
                }

                let currentVector = memory.embeddingVector
                guard !currentVector.isEmpty else { continue }

                // Calculate target vector (average of query vectors)
                var targetVector = [Double](repeating: 0, count: currentVector.count)
                for qv in queryVectors {
                    guard qv.count == currentVector.count else { continue }
                    for i in 0..<currentVector.count {
                        targetVector[i] += qv[i]
                    }
                }

                targetVector = VectorMath.normalize(targetVector)

                // Apply learning rule: V' = V + score * learningRate * (Target - V)
                var newVector = currentVector
                for i in 0..<currentVector.count {
                    let delta = targetVector[i] - currentVector[i]
                    newVector[i] += score * learningRate * delta
                }

                newVector = VectorMath.normalize(newVector)

                try await persistenceService.updateMemoryEmbedding(id: id, newEmbedding: newVector)
                logger.info("Embedded updated for '\(memory.title)' [Score: \(score)]")
            } catch {
                logger.error(
                    "Failed to adjust embedding for \(idString): \(error.localizedDescription)")
            }
        }
    }
}

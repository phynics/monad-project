import MonadShared
import Foundation
import GRDB
import MonadCore
import Testing

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

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0
        for i in 0..<a.count { dot += a[i] * b[i] }
        return dot // Vectors are assumed normalized
    }
}

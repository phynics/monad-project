import Testing
import Foundation
import MonadShared
@testable import MonadCore

struct VectorMathTests {
    // Basic correctness tests
    @Test func testCosineSimilarityCorrectness() async {
        let v1 = [1.0, 0.0, 0.0]
        let v2 = [0.0, 1.0, 0.0]
        let v3 = [1.0, 1.0, 0.0]

        // Orthogonal
        #expect(abs(VectorMath.cosineSimilarity(v1, v2)) < 1e-9)

        // Same direction
        let v4 = [2.0, 2.0, 0.0]
        #expect(abs(VectorMath.cosineSimilarity(v3, v4) - 1.0) < 1e-9)

        // 45 degrees
        let sim = VectorMath.cosineSimilarity(v1, v3)
        // dot = 1, mag1 = 1, mag3 = sqrt(2)
        // 1/sqrt(2) approx 0.70710678
        #expect(abs(sim - (1.0 / sqrt(2.0))) < 1e-9)
    }

    // Benchmark test
    @Test func benchmarkCosineSimilarityLoop() async {
        // Setup
        let dim = 1536
        let count = 1000

        let query = (0..<dim).map { _ in Double.random(in: -1...1) }
        var memories: [[Double]] = []
        for _ in 0..<count {
            memories.append((0..<dim).map { _ in Double.random(in: -1...1) })
        }

        // Measure baseline
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            var hits = 0
            for memory in memories {
                let sim = VectorMath.cosineSimilarity(query, memory)
                if sim > 0.5 { hits += 1 }
            }
        }

        print("Baseline Benchmark: \(elapsed)")
    }
}

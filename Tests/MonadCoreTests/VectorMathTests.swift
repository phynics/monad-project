import Testing
import Foundation
import Accelerate
@testable import MonadCore

@Suite struct VectorMathTests {

    @Test("Magnitude Calculation")
    func testMagnitude() {
        let vector = [3.0, 4.0]
        let magnitude = VectorMath.magnitude(vector)
        #expect(magnitude == 5.0)
    }

    @Test("Cosine Similarity with Pre-calculated Magnitude")
    func testCosineSimilarityOptimized() {
        let a = [1.0, 0.0, 0.0]
        let b = [0.0, 1.0, 0.0]
        let aMag = VectorMath.magnitude(a)
        let similarity = VectorMath.cosineSimilarity(a, b, aMagnitude: aMag)
        #expect(similarity == 0.0)

        let c = [1.0, 1.0]
        let d = [1.0, 1.0]
        let cMag = VectorMath.magnitude(c)
        let sim2 = VectorMath.cosineSimilarity(c, d, aMagnitude: cMag)
        #expect(abs(sim2 - 1.0) < 0.0001)
    }

    @Test("Benchmark Cosine Similarity")
    func benchmarkCosineSimilarity() {
        let dim = 1536
        let count = 10000 // Increased count to make difference measurable
        let a = (0..<dim).map { _ in Double.random(in: -1...1) }
        let vectors = (0..<count).map { _ in (0..<dim).map { _ in Double.random(in: -1...1) } }

        let startStandard = Date()
        var sumStandard = 0.0
        for b in vectors {
            sumStandard += VectorMath.cosineSimilarity(a, b)
        }
        let endStandard = Date()
        let timeStandard = endStandard.timeIntervalSince(startStandard)

        let aMag = VectorMath.magnitude(a)
        let startOptimized = Date()
        var sumOptimized = 0.0
        for b in vectors {
            sumOptimized += VectorMath.cosineSimilarity(a, b, aMagnitude: aMag)
        }
        let endOptimized = Date()
        let timeOptimized = endOptimized.timeIntervalSince(startOptimized)

        print("Standard: \(timeStandard)s, Optimized: \(timeOptimized)s")
        print("Improvement: \(timeStandard / timeOptimized)x")

        #expect(timeOptimized < timeStandard)
    }
}

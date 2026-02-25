import Testing
import Foundation
@testable import MonadCore

@Suite struct VectorMathTests {

    @Test("Cosine Similarity - Basic")
    func testCosineSimilarity() {
        let a = [1.0, 0.0, 0.0]
        let b = [1.0, 0.0, 0.0]
        let sim = VectorMath.cosineSimilarity(a, b)
        #expect(abs(sim - 1.0) < 0.0001)

        let c = [0.0, 1.0, 0.0]
        let sim2 = VectorMath.cosineSimilarity(a, c)
        #expect(abs(sim2 - 0.0) < 0.0001)

        let d = [-1.0, 0.0, 0.0]
        let sim3 = VectorMath.cosineSimilarity(a, d)
        #expect(abs(sim3 - (-1.0)) < 0.0001)
    }

    @Test("Magnitude Calculation")
    func testMagnitude() {
        let a = [3.0, 4.0]
        let mag = VectorMath.magnitude(a)
        #expect(abs(mag - 5.0) < 0.0001)

        let b = [1.0, 1.0, 1.0, 1.0]
        let magB = VectorMath.magnitude(b)
        #expect(abs(magB - 2.0) < 0.0001)
    }

    @Test("Optimized Cosine Similarity")
    func testOptimizedCosineSimilarity() {
        let a = [3.0, 4.0] // Magnitude 5
        let b = [6.0, 8.0] // Magnitude 10

        let magA = VectorMath.magnitude(a)
        let sim = VectorMath.cosineSimilarity(a, b, magnitudeA: magA)

        #expect(abs(sim - 1.0) < 0.0001)

        let c = [3.0, -4.0]
        let sim2 = VectorMath.cosineSimilarity(a, c, magnitudeA: magA)
        // Dot product: 9 - 16 = -7
        // Mags: 5 * 5 = 25
        // Expected: -7/25 = -0.28
        #expect(abs(sim2 - (-0.28)) < 0.0001)
    }
}

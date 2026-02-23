import Testing
@testable import MonadCore

@Suite("VectorMath Tests")
struct VectorMathTests {
    @Test("Cosine Similarity calculation")
    func testCosineSimilarity() {
        let v1 = [1.0, 0.0, 0.0]
        let v2 = [0.0, 1.0, 0.0]
        let v3 = [1.0, 1.0, 0.0]

        // Orthogonal vectors
        #expect(abs(VectorMath.cosineSimilarity(v1, v2)) < 0.0001)

        // Same vector
        #expect(abs(VectorMath.cosineSimilarity(v1, v1) - 1.0) < 0.0001)

        // 45 degrees
        let sim = VectorMath.cosineSimilarity(v1, v3)
        // 1 / sqrt(2) approx 0.7071
        #expect(abs(sim - 0.707106) < 0.0001)
    }

    @Test("Magnitude calculation")
    func testMagnitude() {
        let v1 = [3.0, 4.0]
        // Magnitude should be 5
        #expect(abs(VectorMath.magnitude(v1) - 5.0) < 0.0001)

        let v2 = [1.0, 1.0]
        // Magnitude should be sqrt(2)
        #expect(abs(VectorMath.magnitude(v2) - 1.414213) < 0.0001)
    }

    @Test("Optimized Cosine Similarity with pre-calculated magnitude")
    func testOptimizedCosineSimilarity() {
        let v1 = [3.0, 4.0]
        let v2 = [6.0, 8.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, v2, magnitudeA: mag1)

        #expect(abs(sim - 1.0) < 0.0001)

        let v3 = [1.0, 0.0]
        let v4 = [0.0, 1.0]
        let mag3 = VectorMath.magnitude(v3)
        let sim2 = VectorMath.cosineSimilarity(v3, v4, magnitudeA: mag3)
         #expect(abs(sim2) < 0.0001)
    }
}

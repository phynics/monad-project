import Testing
import Foundation
@testable import MonadCore
@testable import MonadShared

@Suite final class VectorMathTests {

    // MARK: - Magnitude

    @Test

    func testMagnitude() {
        let v1 = [3.0, 4.0]
        let mag = VectorMath.magnitude(v1)
        #expect(mag == 5.0)

        let vEmpty: [Double] = []
        let magEmpty = VectorMath.magnitude(vEmpty)
        #expect(magEmpty == 0.0)
    }

    // MARK: - Cosine Similarity

    @Test

    func testOptimizedCosineSimilarity() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [1.0, 2.0, 3.0]
        let v3 = [-1.0, -2.0, -3.0]

        let mag1 = VectorMath.magnitude(v1)

        let sim1 = VectorMath.cosineSimilarity(v1, magnitudeA: mag1, v2)
        #expect(sim1 == 1.0)

        let sim2 = VectorMath.cosineSimilarity(v1, magnitudeA: mag1, v3)
        #expect(sim2 == -1.0)
    }

    @Test

    func testCosineSimilarityIdenticalVectors() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [1.0, 2.0, 3.0]

        let sim = VectorMath.cosineSimilarity(v1, v2)
        #expect(sim == 1.0)
    }

    @Test

    func testCosineSimilarityOrthogonalVectors() {
        let v1 = [1.0, 0.0]
        let v2 = [0.0, 1.0]

        let sim = VectorMath.cosineSimilarity(v1, v2)
        #expect(sim == 0.0)
    }

    @Test

    func testCosineSimilarityOppositeVectors() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [-1.0, -2.0, -3.0]

        let sim = VectorMath.cosineSimilarity(v1, v2)
        #expect(sim == -1.0)
    }

    @Test

    func testCosineSimilarityDifferentLengths() {
        let v1 = [1.0, 2.0]
        let v2 = [1.0, 2.0, 3.0]

        let sim = VectorMath.cosineSimilarity(v1, v2)
        #expect(sim == 0.0) // Should safeguard against mismatched lengths
    }

    @Test

    func testCosineSimilarityEmptyVectors() {
        let v1: [Double] = []
        let v2: [Double] = []

        let sim = VectorMath.cosineSimilarity(v1, v2)
        #expect(sim == 0.0)
    }

    @Test

    func testCosineSimilarityZeroMagnitude() {
        let v1 = [0.0, 0.0]
        let v2 = [0.0, 0.0]

        let sim = VectorMath.cosineSimilarity(v1, v2)
        #expect(sim == 0.0)
    }

    // MARK: - Normalization

    @Test

    func testNormalizeVector() {
        let v = [3.0, 4.0] // Magnitude = 5.0
        let expected = [0.6, 0.8]

        let normalized = VectorMath.normalize(v)

        #expect(normalized.count == expected.count)
        for (a, b) in zip(normalized, expected) {
            #expect(abs(a - b) < 0.000001)
        }
    }

    @Test

    func testNormalizeEmptyVector() {
        let v: [Double] = []
        let normalized = VectorMath.normalize(v)
        #expect(normalized.isEmpty)
    }

    @Test

    func testNormalizeZeroVector() {
        let v = [0.0, 0.0, 0.0]
        let normalized = VectorMath.normalize(v)
        #expect(normalized == [0.0, 0.0, 0.0])
    }
}

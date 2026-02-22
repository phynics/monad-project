import Testing
import Foundation
@testable import MonadCore

@Suite struct VectorMathTests {

    @Test("Magnitude calculation")
    func testMagnitude() {
        let v1 = [3.0, 4.0]
        let mag1 = VectorMath.magnitude(v1)
        #expect(abs(mag1 - 5.0) < 0.0001)

        let v2 = [1.0, 1.0, 1.0, 1.0]
        let mag2 = VectorMath.magnitude(v2)
        #expect(abs(mag2 - 2.0) < 0.0001)

        let vEmpty: [Double] = []
        #expect(VectorMath.magnitude(vEmpty) == 0.0)
    }

    @Test("Cosine Similarity Overload")
    func testCosineSimilarityOverload() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [4.0, 5.0, 6.0]

        let expected = VectorMath.cosineSimilarity(v1, v2)
        let mag1 = VectorMath.magnitude(v1)
        let actual = VectorMath.cosineSimilarity(v1, v2, magnitudeA: mag1)

        #expect(abs(expected - actual) < 0.0001)

        // Orthogonal vectors
        let v3 = [1.0, 0.0]
        let v4 = [0.0, 1.0]
        let mag3 = VectorMath.magnitude(v3)
        let sim34 = VectorMath.cosineSimilarity(v3, v4, magnitudeA: mag3)
        #expect(abs(sim34) < 0.0001)

        // Identical vectors
        let sim11 = VectorMath.cosineSimilarity(v1, v1, magnitudeA: mag1)
        #expect(abs(sim11 - 1.0) < 0.0001)
    }
}

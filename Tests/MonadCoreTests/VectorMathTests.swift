import Testing
import Foundation
@testable import MonadCore

@Suite struct VectorMathTests {

    @Test("Cosine Similarity Correctness")
    func testCosineSimilarity() {
        let v1 = [1.0, 0.0, 0.0]
        let v2 = [1.0, 0.0, 0.0]
        let sim = VectorMath.cosineSimilarity(v1, v2)
        #expect(abs(sim - 1.0) < 0.0001)

        let v3 = [0.0, 1.0, 0.0]
        let sim2 = VectorMath.cosineSimilarity(v1, v3)
        #expect(abs(sim2 - 0.0) < 0.0001)

        let v4 = [-1.0, 0.0, 0.0]
        let sim3 = VectorMath.cosineSimilarity(v1, v4)
        #expect(abs(sim3 - -1.0) < 0.0001)
    }

    @Test("Magnitude Calculation")
    func testMagnitude() {
       let v = [3.0, 4.0]
       let mag = VectorMath.magnitude(v)
       #expect(abs(mag - 5.0) < 0.0001)
    }

    @Test("Cosine Similarity with Pre-calculated Magnitude")
    func testCosineSimilarityWithMagnitude() {
       let v1 = [3.0, 4.0]
       let v2 = [6.0, 8.0]
       let mag1 = 5.0
       let mag2 = 10.0

       let sim = VectorMath.cosineSimilarity(v1, v2, magnitudeA: mag1, magnitudeB: mag2)
       #expect(abs(sim - 1.0) < 0.0001)
    }
}

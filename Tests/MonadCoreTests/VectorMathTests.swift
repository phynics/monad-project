import Testing
@testable import MonadCore
import Foundation

@Suite struct VectorMathTests {

    @Test func magnitude() {
        let v1 = [3.0, 4.0]
        let m1 = VectorMath.magnitude(v1)
        #expect(abs(m1 - 5.0) < 0.0001)
    }

    @Test func standardCosineSimilarity() {
        let v2 = [1.0, 0.0]
        let v3 = [0.0, 1.0]
        let s1 = VectorMath.cosineSimilarity(v2, v3)
        #expect(abs(s1 - 0.0) < 0.0001) // Orthogonal

        let v4 = [1.0, 0.0]
        let v5 = [1.0, 0.0]
        let s2 = VectorMath.cosineSimilarity(v4, v5)
        #expect(abs(s2 - 1.0) < 0.0001) // Identical

        let v6 = [1.0, 0.0]
        let v7 = [-1.0, 0.0]
        let s3 = VectorMath.cosineSimilarity(v6, v7)
        #expect(abs(s3 - -1.0) < 0.0001) // Opposite
    }

    @Test func optimizedCosineSimilarity() {
        let v1 = [3.0, 4.0]
        let magV1 = VectorMath.magnitude(v1)

        let v8 = [6.0, 8.0] // Same direction as v1, magnitude 10
        let s4 = VectorMath.cosineSimilarity(v1, v8, magnitudeA: magV1)
        #expect(abs(s4 - 1.0) < 0.0001)

        let v9 = [-4.0, 3.0] // Orthogonal to v1
        let s5 = VectorMath.cosineSimilarity(v1, v9, magnitudeA: magV1)
        #expect(abs(s5 - 0.0) < 0.0001)
    }
}

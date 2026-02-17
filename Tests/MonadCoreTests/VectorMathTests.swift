import XCTest
@testable import MonadCore

final class VectorMathTests: XCTestCase {

    func testCosineSimilarity() {
        let v1: [Double] = [1.0, 0.0, 0.0]
        let v2: [Double] = [1.0, 0.0, 0.0]
        let v3: [Double] = [0.0, 1.0, 0.0]
        let v4: [Double] = [-1.0, 0.0, 0.0]
        let v5: [Double] = [1.0, 1.0, 0.0] // magnitude sqrt(2)

        // Identity
        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v2), 1.0, accuracy: 0.0001)

        // Orthogonal
        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v3), 0.0, accuracy: 0.0001)

        // Opposite
        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v4), -1.0, accuracy: 0.0001)

        // 45 degrees
        // dot(v1, v5) = 1*1 + 0*1 + 0*0 = 1
        // mag(v1) = 1
        // mag(v5) = sqrt(2)
        // sim = 1 / sqrt(2) ~= 0.7071
        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v5), 1.0 / sqrt(2.0), accuracy: 0.0001)
    }

    func testCosineSimilarityEmpty() {
        let v1: [Double] = []
        let v2: [Double] = []
        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v2), 0.0)
    }

    func testCosineSimilarityMismatch() {
        let v1: [Double] = [1.0]
        let v2: [Double] = [1.0, 2.0]
        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v2), 0.0)
    }

    // Performance test baseline (commented out as it's not a unit test but a benchmark)
    // func testPerformanceBaseline() {
    //     let query = Array(repeating: 1.0, count: 1536)
    //     let targets = (0..<1000).map { _ in Array(repeating: Double.random(in: -1...1), count: 1536) }
    //
    //     measure {
    //         for target in targets {
    //             _ = VectorMath.cosineSimilarity(query, target)
    //         }
    //     }
    // }
}

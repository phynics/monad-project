import Foundation
import XCTest
@testable import MonadCore

final class VectorMathTests: XCTestCase {

    func testCosineSimilarity() {
        let v1 = [1.0, 0.0, 0.0]
        let v2 = [0.0, 1.0, 0.0]
        let v3 = [1.0, 1.0, 0.0] // normalized: [0.707, 0.707, 0]

        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v2), 0.0, accuracy: 0.0001)
        XCTAssertEqual(VectorMath.cosineSimilarity(v1, v1), 1.0, accuracy: 0.0001)

        let sim13 = VectorMath.cosineSimilarity(v1, v3)
        // dot(v1, v3) = 1. mag(v1)=1, mag(v3)=sqrt(2). sim = 1/1.414 = 0.707
        XCTAssertEqual(sim13, 0.7071, accuracy: 0.0001)
    }

    func testCosineSimilarityPerformance() {
        // Create random vectors of 1536 dimensions (typical embedding size)
        let dim = 1536
        let count = 1000

        let query = (0..<dim).map { _ in Double.random(in: -1...1) }
        let vectors = (0..<count).map { _ in
            (0..<dim).map { _ in Double.random(in: -1...1) }
        }

        measure {
            for v in vectors {
                _ = VectorMath.cosineSimilarity(query, v)
            }
        }
    }
}

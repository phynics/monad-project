import XCTest
@testable import MonadCore

final class VectorMathTests: XCTestCase {

    // Simulate OpenAI embeddings (1536 dimensions)
    let dimensions = 1536
    // Simulate a database of 1000 memories
    let count = 1000

    var query: [Double]!
    var vectors: [[Double]]!

    override func setUp() {
        super.setUp()
        // Initialize random vectors
        query = (0..<dimensions).map { _ in Double.random(in: -1...1) }
        vectors = (0..<count).map { _ in (0..<dimensions).map { _ in Double.random(in: -1...1) } }
    }

    func testCosineSimilarityBaseline() {
        measure {
            for v in vectors {
                _ = VectorMath.cosineSimilarity(query, v)
            }
        }
    }

    func testCosineSimilarityOptimized() {
        measure {
            let magnitude = VectorMath.magnitude(query)
            for v in vectors {
                _ = VectorMath.cosineSimilarity(query, v, magnitudeA: magnitude)
            }
        }
    }
}

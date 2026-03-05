import XCTest
@testable import MonadCore

final class VectorMathTests: XCTestCase {
    
    // MARK: - Cosine Similarity
    
    func testCosineSimilarityIdenticalVectors() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [1.0, 2.0, 3.0]
        
        let sim = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001)
    }
    
    func testCosineSimilarityOrthogonalVectors() {
        let v1 = [1.0, 0.0]
        let v2 = [0.0, 1.0]
        
        let sim = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 0.0, accuracy: 0.0001)
    }
    
    func testCosineSimilarityOppositeVectors() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [-1.0, -2.0, -3.0]
        
        let sim = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(sim, -1.0, accuracy: 0.0001)
    }
    
    func testCosineSimilarityDifferentLengths() {
        let v1 = [1.0, 2.0]
        let v2 = [1.0, 2.0, 3.0]
        
        let sim = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 0.0) // Should safeguard against mismatched lengths
    }
    
    func testCosineSimilarityEmptyVectors() {
        let v1: [Double] = []
        let v2: [Double] = []
        
        let sim = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 0.0)
    }
    
    func testCosineSimilarityZeroMagnitude() {
        let v1 = [0.0, 0.0]
        let v2 = [0.0, 0.0]
        
        let sim = VectorMath.cosineSimilarity(v1, v2)
        XCTAssertEqual(sim, 0.0)
    }
    
    // MARK: - Optimized Cosine Similarity

    func testOptimizedCosineSimilarityIdenticalVectors() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [1.0, 2.0, 3.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, v2, magnitudeA: mag1)
        XCTAssertEqual(sim, 1.0, accuracy: 0.0001)
    }

    func testOptimizedCosineSimilarityOrthogonalVectors() {
        let v1 = [1.0, 0.0]
        let v2 = [0.0, 1.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, v2, magnitudeA: mag1)
        XCTAssertEqual(sim, 0.0, accuracy: 0.0001)
    }

    func testOptimizedCosineSimilarityDifferentLengths() {
        let v1 = [1.0, 2.0]
        let v2 = [1.0, 2.0, 3.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, v2, magnitudeA: mag1)
        XCTAssertEqual(sim, 0.0)
    }

    func testOptimizedCosineSimilarityZeroMagnitude() {
        let v1 = [0.0, 0.0]
        let v2 = [0.0, 0.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, v2, magnitudeA: mag1)
        XCTAssertEqual(sim, 0.0)
    }

    // MARK: - Magnitude

    func testMagnitudeNormalVector() {
        let v = [3.0, 4.0]
        let mag = VectorMath.magnitude(v)
        XCTAssertEqual(mag, 5.0, accuracy: 0.0001)
    }

    func testMagnitudeEmptyVector() {
        let v: [Double] = []
        let mag = VectorMath.magnitude(v)
        XCTAssertEqual(mag, 0.0)
    }

    func testMagnitudeZeroVector() {
        let v = [0.0, 0.0, 0.0]
        let mag = VectorMath.magnitude(v)
        XCTAssertEqual(mag, 0.0)
    }

    // MARK: - Normalization
    
    func testNormalizeVector() {
        let v = [3.0, 4.0] // Magnitude = 5.0
        let expected = [0.6, 0.8]
        
        let normalized = VectorMath.normalize(v)
        
        XCTAssertEqual(normalized.count, expected.count)
        for (a, b) in zip(normalized, expected) {
            XCTAssertEqual(a, b, accuracy: 0.0001)
        }
    }
    
    func testNormalizeEmptyVector() {
        let v: [Double] = []
        let normalized = VectorMath.normalize(v)
        XCTAssertTrue(normalized.isEmpty)
    }
    
    func testNormalizeZeroVector() {
        let v = [0.0, 0.0, 0.0]
        let normalized = VectorMath.normalize(v)
        XCTAssertEqual(normalized, [0.0, 0.0, 0.0])
    }
}

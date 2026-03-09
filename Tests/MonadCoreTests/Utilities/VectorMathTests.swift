import Testing
import Foundation
@testable import MonadCore
@testable import MonadShared

@Suite final class VectorMathTests {
    
    // MARK: - Cosine Similarity
    
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
    
    // MARK: - Optimized Cosine Similarity

    @Test

    func testOptimizedCosineSimilarityIdenticalVectors() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [1.0, 2.0, 3.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, magnitudeA: mag1, v2)

        #expect(abs(sim - 1.0) < 0.000001)
    }

    @Test

    func testOptimizedCosineSimilarityOppositeVectors() {
        let v1 = [1.0, 2.0, 3.0]
        let v2 = [-1.0, -2.0, -3.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, magnitudeA: mag1, v2)

        #expect(abs(sim - (-1.0)) < 0.000001)
    }

    @Test

    func testOptimizedCosineSimilarityWithZeroMagnitude() {
        let v1 = [0.0, 0.0]
        let v2 = [1.0, 1.0]

        let mag1 = VectorMath.magnitude(v1)
        let sim = VectorMath.cosineSimilarity(v1, magnitudeA: mag1, v2)
        #expect(sim == 0.0)
    }

    // MARK: - Magnitude

    @Test

    func testMagnitude() {
        let v = [3.0, 4.0] // 3^2 + 4^2 = 9 + 16 = 25, sqrt(25) = 5
        let mag = VectorMath.magnitude(v)
        #expect(mag == 5.0)
    }

    @Test

    func testMagnitudeEmptyVector() {
        let v: [Double] = []
        let mag = VectorMath.magnitude(v)
        #expect(mag == 0.0)
    }

    @Test

    func testMagnitudeZeroVector() {
        let v = [0.0, 0.0, 0.0]
        let mag = VectorMath.magnitude(v)
        #expect(mag == 0.0)
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

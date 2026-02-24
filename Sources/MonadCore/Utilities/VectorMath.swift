import MonadShared
import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Shared math utilities for vector operations using Apple's Accelerate framework where available
public enum VectorMath {

    /// Calculate the magnitude (Euclidean norm) of a vector
    /// - Parameter v: The vector
    /// - Returns: The magnitude
    public static func magnitude(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0.0 }

        #if canImport(Accelerate)
        var sumSq: Double = 0.0
        vDSP_svesqD(v, 1, &sumSq, vDSP_Length(v.count))
        return sqrt(sumSq)
        #else
        // Pure Swift implementation for Linux
        return sqrt(v.reduce(0) { $0 + $1 * $1 })
        #endif
    }

    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        let magA = magnitude(a)
        return cosineSimilarity(a, b, magnitudeA: magA)
    }

    /// Optimized cosine similarity with pre-calculated magnitude for the first vector
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    ///   - magnitudeA: Pre-calculated magnitude of vector 'a'
    /// - Returns: Similarity score
    public static func cosineSimilarity(_ a: [Double], _ b: [Double], magnitudeA: Double) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        guard magnitudeA > 0 else { return 0.0 }
        
        #if canImport(Accelerate)
        var dotProduct: Double = 0.0
        vDSP_dotprD(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        var sumSqB: Double = 0.0
        vDSP_svesqD(b, 1, &sumSqB, vDSP_Length(b.count))
        
        let magnitudeB = sqrt(sumSqB)
        guard magnitudeB > 0 else { return 0.0 }
        
        return dotProduct / (magnitudeA * magnitudeB)
        #else
        // Pure Swift implementation
        var dotProduct: Double = 0.0
        var sumSqB: Double = 0.0

        // Single loop for efficiency
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            sumSqB += b[i] * b[i]
        }

        let magnitudeB = sqrt(sumSqB)
        guard magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
        #endif
    }

    /// Normalize a vector to unit length
    /// - Parameter v: Vector to normalize
    /// - Returns: Normalized vector
    public static func normalize(_ v: [Double]) -> [Double] {
        guard !v.isEmpty else { return v }
        
        let mag = magnitude(v)
        guard mag > 0 else { return v }
        
        #if canImport(Accelerate)
        var result = [Double](repeating: 0.0, count: v.count)
        var divisor = mag
        vDSP_vsdivD(v, 1, &divisor, &result, 1, vDSP_Length(v.count))
        return result
        #else
        return v.map { $0 / mag }
        #endif
    }
}

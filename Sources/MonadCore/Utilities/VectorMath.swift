import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Shared math utilities for vector operations using Apple's Accelerate framework
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
        // Manual calculation for Linux compatibility
        let sumSq = v.reduce(0.0) { $0 + ($1 * $1) }
        return sqrt(sumSq)
        #endif
    }

    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }

        // Use the pre-calculated magnitude version if available to be consistent,
        // but for a single call, we just compute both magnitudes.
        let magA = magnitude(a)
        let magB = magnitude(b)

        guard magA > 0, magB > 0 else { return 0.0 }

        #if canImport(Accelerate)
        var dotProduct: Double = 0.0
        vDSP_dotprD(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        #else
        let dotProduct = zip(a, b).reduce(0.0) { $0 + ($1 * $2) }
        #endif

        return dotProduct / (magA * magB)
    }

    /// Calculate cosine similarity with a pre-calculated magnitude for the first vector.
    /// This is optimized for searching where 'a' is the query vector (constant across iterations).
    /// - Parameters:
    ///   - a: First vector (query)
    ///   - b: Second vector (target)
    ///   - magnitudeA: Pre-calculated magnitude of vector 'a'
    /// - Returns: Similarity score
    public static func cosineSimilarity(_ a: [Double], _ b: [Double], magnitudeA: Double) -> Double {
        guard a.count == b.count, !a.isEmpty, magnitudeA > 0 else { return 0.0 }

        let magB = magnitude(b)
        guard magB > 0 else { return 0.0 }

        #if canImport(Accelerate)
        var dotProduct: Double = 0.0
        vDSP_dotprD(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        #else
        let dotProduct = zip(a, b).reduce(0.0) { $0 + ($1 * $2) }
        #endif

        return dotProduct / (magnitudeA * magB)
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

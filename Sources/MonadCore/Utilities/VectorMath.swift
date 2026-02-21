import MonadShared
import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Shared math utilities for vector operations using Apple's Accelerate framework
public enum VectorMath {
    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        let magA = magnitude(a)
        return cosineSimilarity(a, b, magA: magA)
    }

    /// Calculate cosine similarity between two vectors, with pre-calculated magnitude for the first vector
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    ///   - magA: Pre-calculated magnitude of the first vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ a: [Double], _ b: [Double], magA: Double) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        
        #if canImport(Accelerate)
        var dotProduct: Double = 0.0
        vDSP_dotprD(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        let magB = magnitude(b)

        let magnitudes = magA * magB
        guard magnitudes > 0 else { return 0.0 }
        
        return dotProduct / magnitudes
        #else
        var dotProduct: Double = 0.0
        var sumSqB: Double = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            sumSqB += b[i] * b[i]
        }

        let magB = sqrt(sumSqB)
        let magnitudes = magA * magB
        guard magnitudes > 0 else { return 0.0 }
        
        return dotProduct / magnitudes
        #endif
    }

    /// Calculate the Euclidean magnitude (norm) of a vector
    /// - Parameter v: The vector
    /// - Returns: The magnitude
    public static func magnitude(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0.0 }

        #if canImport(Accelerate)
        var sumSq: Double = 0.0
        vDSP_svesqD(v, 1, &sumSq, vDSP_Length(v.count))
        return sqrt(sumSq)
        #else
        var sumSq: Double = 0.0
        for x in v {
            sumSq += x * x
        }
        return sqrt(sumSq)
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

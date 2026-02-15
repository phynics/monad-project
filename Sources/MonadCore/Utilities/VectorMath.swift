import Foundation
import Accelerate

/// Shared math utilities for vector operations using Apple's Accelerate framework
public enum VectorMath {
    /// Calculate magnitude (L2 norm) of a vector
    /// - Parameter v: Vector
    /// - Returns: Magnitude
    public static func magnitude(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0.0 }
        var sumSq: Double = 0.0
        vDSP_svesqD(v, 1, &sumSq, vDSP_Length(v.count))
        return sqrt(sumSq)
    }

    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    ///   - magnitudeA: Optional pre-calculated magnitude of vector a
    ///   - magnitudeB: Optional pre-calculated magnitude of vector b
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ a: [Double], _ b: [Double], magnitudeA: Double? = nil, magnitudeB: Double? = nil) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        
        var dotProduct: Double = 0.0
        vDSP_dotprD(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        
        let magA = magnitudeA ?? magnitude(a)
        let magB = magnitudeB ?? magnitude(b)
        
        let magnitudes = magA * magB
        guard magnitudes > 0 else { return 0.0 }
        
        return dotProduct / magnitudes
    }

    /// Normalize a vector to unit length
    /// - Parameter v: Vector to normalize
    /// - Returns: Normalized vector
    public static func normalize(_ v: [Double]) -> [Double] {
        guard !v.isEmpty else { return v }
        
        var sumSq: Double = 0.0
        vDSP_svesqD(v, 1, &sumSq, vDSP_Length(v.count))
        
        let magnitude = sqrt(sumSq)
        guard magnitude > 0 else { return v }
        
        var result = [Double](repeating: 0.0, count: v.count)
        var divisor = magnitude
        vDSP_vsdivD(v, 1, &divisor, &result, 1, vDSP_Length(v.count))
        
        return result
    }
}

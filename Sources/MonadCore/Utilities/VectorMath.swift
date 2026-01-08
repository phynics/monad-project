import Foundation

/// Shared math utilities for vector operations
public enum VectorMath {
    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - a: First vector
    ///   - b: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let magnitudes = sqrt(magA) * sqrt(magB)
        guard magnitudes > 0 else { return 0.0 }
        return dot / magnitudes
    }

    /// Normalize a vector to unit length
    /// - Parameter v: Vector to normalize
    /// - Returns: Normalized vector
    public static func normalize(_ v: [Double]) -> [Double] {
        let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }
}

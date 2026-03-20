import MonadShared
import Foundation
import Accelerate

/// Shared math utilities for vector operations using Apple's Accelerate framework
public enum VectorMath {
    /// Calculate the Euclidean magnitude of a vector
    /// - Parameter vector: The vector to calculate the magnitude for
    /// - Returns: The Euclidean magnitude
    public static func magnitude(_ vector: [Double]) -> Double {
        guard !vector.isEmpty else { return 0.0 }
        var sumSq: Double = 0.0
        vDSP_svesqD(vector, 1, &sumSq, vDSP_Length(vector.count))
        return sqrt(sumSq)
    }

    /// Optimized calculation of cosine similarity when one magnitude is pre-calculated
    /// Useful for loops where vectorA is a constant query vector.
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - magnitudeA: Pre-calculated magnitude of the first vector
    ///   - vectorB: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ vectorA: [Double], magnitudeA: Double, _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty, magnitudeA > 0 else { return 0.0 }

        var dotProduct: Double = 0.0
        vDSP_dotprD(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))

        var sumSqB: Double = 0.0
        vDSP_svesqD(vectorB, 1, &sumSqB, vDSP_Length(vectorB.count))

        let magnitudeB = sqrt(sumSqB)
        guard magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - vectorB: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        let magA = magnitude(vectorA)
        return cosineSimilarity(vectorA, magnitudeA: magA, vectorB)
    }

    /// Normalize a vector to unit length
    /// - Parameter vector: Vector to normalize
    /// - Returns: Normalized vector
    public static func normalize(_ vector: [Double]) -> [Double] {
        guard !vector.isEmpty else { return vector }

        var sumSq: Double = 0.0
        vDSP_svesqD(vector, 1, &sumSq, vDSP_Length(vector.count))

        let magnitude = sqrt(sumSq)
        guard magnitude > 0 else { return vector }

        var result = [Double](repeating: 0.0, count: vector.count)
        var divisor = magnitude
        vDSP_vsdivD(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))

        return result
    }
}

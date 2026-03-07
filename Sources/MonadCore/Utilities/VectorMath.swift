import MonadShared
import Foundation
import Accelerate

/// Shared math utilities for vector operations using Apple's Accelerate framework
public enum VectorMath {
    /// Calculate the Euclidean magnitude (norm) of a vector
    /// - Parameter vector: Vector to calculate the magnitude for
    /// - Returns: Magnitude
    public static func magnitude(_ vector: [Double]) -> Double {
        guard !vector.isEmpty else { return 0.0 }
        var sumSq: Double = 0.0
        vDSP_svesqD(vector, 1, &sumSq, vDSP_Length(vector.count))
        return sqrt(sumSq)
    }

    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - vectorB: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else { return 0.0 }

        var dotProduct: Double = 0.0
        vDSP_dotprD(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))

        let magA = magnitude(vectorA)
        let magB = magnitude(vectorB)

        let magnitudes = magA * magB
        guard magnitudes > 0 else { return 0.0 }

        return dotProduct / magnitudes
    }

    /// Calculate cosine similarity using a pre-calculated magnitude for the first vector.
    /// This is an optimization for loops where the first vector (e.g., query) remains constant.
    /// - Parameters:
    ///   - vectorA: First vector (e.g., query)
    ///   - magnitudeA: Pre-calculated magnitude of vectorA
    ///   - vectorB: Second vector (e.g., memory embedding)
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ vectorA: [Double], magnitudeA: Double, _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else { return 0.0 }

        var dotProduct: Double = 0.0
        vDSP_dotprD(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))

        let magB = magnitude(vectorB)
        let magnitudes = magnitudeA * magB

        guard magnitudes > 0 else { return 0.0 }

        return dotProduct / magnitudes
    }

    /// Normalize a vector to unit length
    /// - Parameter vector: Vector to normalize
    /// - Returns: Normalized vector
    public static func normalize(_ vector: [Double]) -> [Double] {
        guard !vector.isEmpty else { return vector }

        let mag = magnitude(vector)
        guard mag > 0 else { return vector }

        var result = [Double](repeating: 0.0, count: vector.count)
        var divisor = mag
        vDSP_vsdivD(vector, 1, &divisor, &result, 1, vDSP_Length(vector.count))

        return result
    }
}

import MonadShared
import Foundation
import Accelerate

/// Shared math utilities for vector operations using Apple's Accelerate framework
public enum VectorMath {
    /// Calculate magnitude (Euclidean norm) of a vector
    /// - Parameter vector: Vector to calculate magnitude for
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
        let magA = magnitude(vectorA)
        return cosineSimilarity(vectorA, vectorB, magnitudeA: magA)
    }

    /// Calculate cosine similarity between two vectors, with a pre-calculated magnitude for the first vector
    /// This is an optimization for comparing a single vector against many others in a loop
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - vectorB: Second vector
    ///   - magnitudeA: Pre-calculated magnitude of vectorA
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double], magnitudeA: Double) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty, magnitudeA > 0 else { return 0.0 }

        var dotProduct: Double = 0.0
        vDSP_dotprD(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))

        let magnitudeB = magnitude(vectorB)
        let magnitudes = magnitudeA * magnitudeB
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

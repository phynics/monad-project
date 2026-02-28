import Foundation
import Accelerate

/// Shared math utilities for vector operations using Apple's Accelerate framework
public enum VectorMath {
    /// Calculate cosine similarity between two vectors
    /// - Parameters:
    ///   - vectorA: First vector
    ///   - vectorB: Second vector
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double]) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty else { return 0.0 }

        var dotProduct: Double = 0.0
        vDSP_dotprD(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))

        var sumSqA: Double = 0.0
        vDSP_svesqD(vectorA, 1, &sumSqA, vDSP_Length(vectorA.count))

        var sumSqB: Double = 0.0
        vDSP_svesqD(vectorB, 1, &sumSqB, vDSP_Length(vectorB.count))

        let magnitudes = sqrt(sumSqA) * sqrt(sumSqB)
        guard magnitudes > 0 else { return 0.0 }

        return dotProduct / magnitudes
    }

    /// Calculate cosine similarity between two vectors, with a pre-calculated magnitude for the first vector.
    /// This is an optimization for comparing one query vector against many target vectors.
    /// - Parameters:
    ///   - vectorA: First vector (query)
    ///   - vectorB: Second vector (target)
    ///   - magnitudeA: Pre-calculated magnitude of vectorA
    /// - Returns: Similarity score from -1.0 to 1.0 (0.0 if invalid)
    public static func cosineSimilarity(_ vectorA: [Double], _ vectorB: [Double], magnitudeA: Double) -> Double {
        guard vectorA.count == vectorB.count, !vectorA.isEmpty, magnitudeA > 0 else { return 0.0 }

        var dotProduct: Double = 0.0
#if canImport(Accelerate)
        vDSP_dotprD(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))
#else
        for i in 0..<vectorA.count {
            dotProduct += vectorA[i] * vectorB[i]
        }
#endif

        var sumSqB: Double = 0.0
#if canImport(Accelerate)
        vDSP_svesqD(vectorB, 1, &sumSqB, vDSP_Length(vectorB.count))
#else
        for val in vectorB {
            sumSqB += val * val
        }
#endif

        let magnitudeB = sqrt(sumSqB)
        guard magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Calculate the Euclidean magnitude (L2 norm) of a vector.
    /// - Parameter vector: The vector
    /// - Returns: The magnitude
    public static func magnitude(_ vector: [Double]) -> Double {
        guard !vector.isEmpty else { return 0.0 }

        var sumSq: Double = 0.0
#if canImport(Accelerate)
        vDSP_svesqD(vector, 1, &sumSq, vDSP_Length(vector.count))
#else
        for val in vector {
            sumSq += val * val
        }
#endif
        return sqrt(sumSq)
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

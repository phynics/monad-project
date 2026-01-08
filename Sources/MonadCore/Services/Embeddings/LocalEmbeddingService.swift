import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Embedding service using Apple's NaturalLanguage framework
public final class LocalEmbeddingService: EmbeddingService {
    public init() {}
    
    public func generateEmbedding(for text: String) async throws -> [Double] {
        #if canImport(NaturalLanguage)
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            throw EmbeddingError.modelUnavailable
        }
        
        guard let vector = embedding.vector(for: text) else {
            throw EmbeddingError.generationFailed
        }
        
        return vector
        #else
        throw EmbeddingError.platformNotSupported
        #endif
    }
    
    public func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
        var results: [[Double]] = []
        for text in texts {
            results.append(try await generateEmbedding(for: text))
        }
        return results
    }
}

public enum EmbeddingError: LocalizedError {
    case modelUnavailable
    case generationFailed
    case platformNotSupported
    
    public var errorDescription: String? {
        switch self {
        case .modelUnavailable:
            return "NaturalLanguage embedding model is unavailable."
        case .generationFailed:
            return "Failed to generate embedding vector."
        case .platformNotSupported:
            return "Local embeddings are only supported on Apple platforms (macOS, iOS, etc)."
        }
    }
}

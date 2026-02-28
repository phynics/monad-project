import Foundation

/// Error types specific to ContextManager
public enum ContextManagerError: LocalizedError {
    /// Embedding generation failed
    case embeddingFailed(Error)
    /// Database retrieval failed
    case persistenceFailed(Error)
    /// Tag generation failed (non-critical)
    case tagGenerationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .embeddingFailed(let error): return "Embedding failed: \(error.localizedDescription)"
        case .persistenceFailed(let error): return "Database error: \(error.localizedDescription)"
        case .tagGenerationFailed(let error): return "Tag generation failed: \(error.localizedDescription)"
        }
    }
}

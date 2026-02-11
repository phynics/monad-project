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
        case .embeddingFailed(let e): return "Embedding failed: \(e.localizedDescription)"
        case .persistenceFailed(let e): return "Database error: \(e.localizedDescription)"
        case .tagGenerationFailed(let e): return "Tag generation failed: \(e.localizedDescription)"
        }
    }
}

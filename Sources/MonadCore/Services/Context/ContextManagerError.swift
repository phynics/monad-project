import ErrorKit
import Foundation
import MonadShared

/// Error types specific to ContextManager
public enum ContextManagerError: Throwable {
    /// Embedding generation failed
    case embeddingFailed(Error)
    /// Database retrieval failed
    case persistenceFailed(Error)

    public var errorDescription: String? {
        switch self {
        case let .embeddingFailed(error): return "Embedding failed: \(error.localizedDescription)"
        case let .persistenceFailed(error): return "Database error: \(error.localizedDescription)"
        }
    }

    public var userFriendlyMessage: String {
        switch self {
        case .embeddingFailed:
            return "Failed to analyze your request for relevant context."
        case .persistenceFailed:
            return "Could not retrieve saved memories or notes."
        }
    }
}

import Foundation
import MonadShared

/// Results from a memory retrieval operation.
public struct MemoryRetrievalResult: Sendable {
    public let memories: [SemanticSearchResult]
    public let tags: [String]
    public let vector: [Double]
    public let semanticResults: [SemanticSearchResult]
    public let tagResults: [Memory]

    public init(
        memories: [SemanticSearchResult],
        tags: [String],
        vector: [Double],
        semanticResults: [SemanticSearchResult],
        tagResults: [Memory]
    ) {
        self.memories = memories
        self.tags = tags
        self.vector = vector
        self.semanticResults = semanticResults
        self.tagResults = tagResults
    }
}

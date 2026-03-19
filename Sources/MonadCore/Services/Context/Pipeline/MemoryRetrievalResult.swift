import Foundation
import MonadShared

/// Results from a memory retrieval operation.
public struct MemoryRetrievalResult: Sendable {
    /// Merged and ranked memories.
    public let memories: [SemanticSearchResult]
    /// Tags generated for the retrieval context.
    public let tags: [String]
    /// The embedding vector generated for the query.
    public let vector: [Double]
    /// Raw results from semantic search.
    public let semanticResults: [SemanticSearchResult]
    /// Raw results from tag-based search.
    public let tagResults: [Memory]

    /// Initializes a new memory retrieval result.
    /// - Parameters:
    ///   - memories: The final ranked memories.
    ///   - tags: The tags used for retrieval.
    ///   - vector: The query embedding vector.
    ///   - semanticResults: All semantic matches found.
    ///   - tagResults: All tag matches found.
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

import Foundation
import MonadShared

/// Shared context state during the gathering pipeline
public actor ContextPipelineContext {
    /// The original user query.
    public let query: String
    /// Recent conversation history.
    public let history: [Message]
    /// Maximum number of results to retrieve.
    public let limit: Int
    /// Optional closure to generate tags from a string.
    public let tagGenerator: (@Sendable (String) async throws -> [String])?
    /// The time when the pipeline execution started.
    public let startTime: CFAbsoluteTime

    /// The query after being augmented with history/context.
    public private(set) var augmentedQuery: String = ""
    /// Discovered filesystem notes.
    public private(set) var notes: [ContextFile] = []
    /// Final merged semantic memories.
    public private(set) var memories: [SemanticSearchResult] = []
    /// Tags generated for the current query.
    public private(set) var generatedTags: [String] = []
    /// Vector representation of the query.
    public private(set) var queryVector: [Double] = []
    /// Raw semantic search results before ranking.
    public private(set) var semanticResults: [SemanticSearchResult] = []
    /// Raw tag-based search results before ranking.
    public private(set) var tagResults: [Memory] = []
    /// The final assembled context data.
    public private(set) var contextData: ContextData?

    /// Initializes a new pipeline context.
    /// - Parameters:
    ///   - query: The user's input query.
    ///   - history: Recent conversation messages.
    ///   - limit: Result limit for retrieval.
    ///   - tagGenerator: Optional tag generation logic.
    ///   - startTime: Pipeline start timestamp.
    public init(
        query: String,
        history: [Message],
        limit: Int,
        tagGenerator: (@Sendable (String) async throws -> [String])?,
        startTime: CFAbsoluteTime
    ) {
        self.query = query
        self.history = history
        self.limit = limit
        self.tagGenerator = tagGenerator
        self.startTime = startTime
    }

    /// Assembles and sets the final context data object.
    /// - Parameter executionTime: The total time taken to gather context.
    /// - Returns: The final context data.
    @discardableResult
    public func finalize(executionTime: TimeInterval) -> ContextData {
        let data = ContextData(
            notes: notes,
            memories: memories,
            generatedTags: generatedTags,
            queryVector: queryVector,
            augmentedQuery: augmentedQuery,
            semanticResults: semanticResults,
            tagResults: tagResults,
            executionTime: executionTime
        )
        self.contextData = data
        return data
    }

    /// Sets the augmented version of the search query.
    /// - Parameter query: The augmented query string.
    public func setAugmentedQuery(_ query: String) {
        augmentedQuery = query
    }

    /// Updates the gathered results in the context.
    /// - Parameters:
    ///   - notes: Discovered notes.
    ///   - memories: Final ranked memories.
    ///   - tags: Generated tags.
    ///   - vector: Query embedding vector.
    ///   - semanticResults: Raw semantic matches.
    ///   - tagResults: Raw tag matches.
    public func setResults(
        notes: [ContextFile]? = nil,
        memories: [SemanticSearchResult]? = nil,
        tags: [String]? = nil,
        vector: [Double]? = nil,
        semanticResults: [SemanticSearchResult]? = nil,
        tagResults: [Memory]? = nil
    ) {
        if let notes { self.notes = notes }
        if let memories { self.memories = memories }
        if let tags { generatedTags = tags }
        if let vector { queryVector = vector }
        if let semanticResults { self.semanticResults = semanticResults }
        if let tagResults { self.tagResults = tagResults }
    }
}

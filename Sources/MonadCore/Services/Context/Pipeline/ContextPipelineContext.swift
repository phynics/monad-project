import Foundation
import MonadShared

/// Shared context state during the gathering pipeline
public actor ContextPipelineContext {
    public let query: String
    public let history: [Message]
    public let limit: Int
    public let tagGenerator: (@Sendable (String) async throws -> [String])?
    public let startTime: CFAbsoluteTime

    public private(set) var augmentedQuery: String = ""
    public private(set) var notes: [ContextFile] = []
    public private(set) var memories: [SemanticSearchResult] = []
    public private(set) var generatedTags: [String] = []
    public private(set) var queryVector: [Double] = []
    public private(set) var semanticResults: [SemanticSearchResult] = []
    public private(set) var tagResults: [Memory] = []
    public private(set) var contextData: ContextData?

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

    public func getResults() -> (notes: [ContextFile], memories: [SemanticSearchResult], tags: [String], vector: [Double], semanticResults: [SemanticSearchResult], tagResults: [Memory]) {
        (notes, memories, generatedTags, queryVector, semanticResults, tagResults)
    }

    public func setAugmentedQuery(_ query: String) {
        augmentedQuery = query
    }

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

    public func setContextData(_ data: ContextData) {
        contextData = data
    }
}

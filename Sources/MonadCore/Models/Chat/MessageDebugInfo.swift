import MonadShared
import Foundation

/// Debug information for messages (not persisted)
public struct MessageDebugInfo: Equatable, Sendable, Codable {
    /// For user messages: the full raw prompt sent to LLM (with context, notes, etc.)
    public var rawPrompt: String?

    /// For assistant messages: OpenAI API response metadata
    public var apiResponse: APIResponseMetadata?

    /// For assistant messages: original unparsed response from LLM
    public var originalResponse: String?

    /// For assistant messages: parsed content (after removing <think> tags)
    public var parsedContent: String?

    /// For assistant messages: parsed thinking block
    public var parsedThinking: String?

    /// For assistant messages: parsed tool calls
    public var parsedToolCalls: [ToolCall]?

    /// For user messages: relevant memories found for this message with similarity info
    public var contextMemories: [SemanticSearchResult]?

    /// For user messages: tags generated for search
    public var generatedTags: [String]?

    /// For user messages: query embedding vector
    public var queryVector: [Double]?

    /// For user messages: the query after history augmentation
    public var augmentedQuery: String?

    /// For user messages: top semantic search candidates before ranking
    public var semanticResults: [SemanticSearchResult]?

    /// For user messages: keyword/tag search matches
    public var tagResults: [Memory]?

    /// Subagent context info
    public var subagentContext: SubagentContext?

    /// For user messages: structured map of prompt sections (e.g. "system" -> content)
    public var structuredContext: [String: String]?

    /// Default empty initializer for fallback scenarios
    public init(
        rawPrompt: String? = nil,
        apiResponse: APIResponseMetadata? = nil,
        originalResponse: String? = nil,
        parsedContent: String? = nil,
        parsedThinking: String? = nil,
        parsedToolCalls: [ToolCall]? = nil,
        contextMemories: [SemanticSearchResult]? = nil,
        generatedTags: [String]? = nil,
        queryVector: [Double]? = nil,
        augmentedQuery: String? = nil,
        semanticResults: [SemanticSearchResult]? = nil,
        tagResults: [Memory]? = nil,
        subagentContext: SubagentContext? = nil,
        structuredContext: [String: String]? = nil
    ) {
        self.rawPrompt = rawPrompt
        self.apiResponse = apiResponse
        self.originalResponse = originalResponse
        self.parsedContent = parsedContent
        self.parsedThinking = parsedThinking
        self.parsedToolCalls = parsedToolCalls
        self.contextMemories = contextMemories
        self.generatedTags = generatedTags
        self.queryVector = queryVector
        self.augmentedQuery = augmentedQuery
        self.semanticResults = semanticResults
        self.tagResults = tagResults
        self.subagentContext = subagentContext
        self.structuredContext = structuredContext
    }

    public static func userMessage(
        rawPrompt: String,
        contextMemories: [SemanticSearchResult]? = nil,
        generatedTags: [String]? = nil,
        queryVector: [Double]? = nil,
        augmentedQuery: String? = nil,
        semanticResults: [SemanticSearchResult]? = nil,
        tagResults: [Memory]? = nil,
        structuredContext: [String: String]? = nil
    ) -> MessageDebugInfo {
        MessageDebugInfo(
            rawPrompt: rawPrompt,
            apiResponse: nil,
            originalResponse: nil,
            parsedContent: nil,
            parsedThinking: nil,
            parsedToolCalls: nil,
            contextMemories: contextMemories,
            generatedTags: generatedTags,
            queryVector: queryVector,
            augmentedQuery: augmentedQuery,
            semanticResults: semanticResults,
            tagResults: tagResults,
            structuredContext: structuredContext
        )
    }

    public static func assistantMessage(
        response: APIResponseMetadata,
        original: String? = nil,
        parsed: String? = nil,
        thinking: String? = nil,
        toolCalls: [ToolCall]? = nil,
        subagentContext: SubagentContext? = nil,
        rawPrompt: String? = nil,
        structuredContext: [String: String]? = nil
    ) -> MessageDebugInfo {
        MessageDebugInfo(
            rawPrompt: rawPrompt,
            apiResponse: response,
            originalResponse: original,
            parsedContent: parsed,
            parsedThinking: thinking,
            parsedToolCalls: toolCalls,
            contextMemories: nil,
            generatedTags: nil,
            queryVector: nil,
            augmentedQuery: nil,
            semanticResults: nil,
            tagResults: nil,
            subagentContext: subagentContext,
            structuredContext: structuredContext
        )
    }
}

import Foundation

// MARK: - Subagent Context

/// Context information for a subagent execution
public struct SubagentContext: Equatable, Sendable, Codable {
    public let prompt: String
    public let documents: [String]  // Paths
    public let rawResponse: String?  // Full output including thinking

    public init(prompt: String, documents: [String], rawResponse: String? = nil) {
        self.prompt = prompt
        self.documents = documents
        self.rawResponse = rawResponse
    }
}

// MARK: - Tool Call

/// Represents a tool call from the LLM
public struct ToolCall: Identifiable, Equatable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public let arguments: [String: AnyCodable]

    public init(name: String, arguments: [String: AnyCodable]) {
        self.id = UUID()
        self.name = name
        self.arguments = arguments
    }

    enum CodingKeys: String, CodingKey {
        case id, name, arguments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.arguments = try container.decode([String: AnyCodable].self, forKey: .arguments)
    }

    public static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.name == rhs.name && lhs.arguments == rhs.arguments
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(arguments)
    }
}

// MARK: - Debug Info

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

/// OpenAI API response metadata
public struct APIResponseMetadata: Equatable, Sendable, Codable {
    public var model: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var finishReason: String?
    public var systemFingerprint: String?
    public var duration: TimeInterval?
    public var tokensPerSecond: Double?

    public init(
        model: String? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil,
        totalTokens: Int? = nil, finishReason: String? = nil, systemFingerprint: String? = nil,
        duration: TimeInterval? = nil, tokensPerSecond: Double? = nil
    ) {
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.finishReason = finishReason
        self.systemFingerprint = systemFingerprint
        self.duration = duration
        self.tokensPerSecond = tokensPerSecond
    }
}

// MARK: - SemanticSearchResult Codable

extension SemanticSearchResult: Codable {
    enum CodingKeys: String, CodingKey {
        case memory, similarity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.memory = try container.decode(Memory.self, forKey: .memory)
        self.similarity = try container.decodeIfPresent(Double.self, forKey: .similarity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(memory, forKey: .memory)
        try container.encodeIfPresent(similarity, forKey: .similarity)
    }
}

import Foundation

/// UI message model for chat interface
///
/// Supports Chain of Thought (CoT) reasoning models that use `<think>` tags
/// to show their reasoning process separately from the final answer.
public struct Message: Identifiable, Equatable, Sendable {
    public let id = UUID()

    /// The main response content (with <think> tags removed)
    public let content: String

    public let role: MessageRole
    public let timestamp = Date()

    /// Chain of Thought reasoning extracted from <think>...</think> blocks
    /// Only present for models that support reasoning tags (e.g., DeepSeek R1, QwQ)
    public let think: String?

    /// Tool calls extracted from <tool_call>...</tool_call> blocks
    public let toolCalls: [ToolCall]?

    /// Debug info - not persisted
    public var debugInfo: MessageDebugInfo?

    /// Optional ID of the parent message in the forest structure
    public var parentId: UUID?

    /// Current progress of context gathering (only for user messages)
    public var gatheringProgress: ContextGatheringProgress?

    /// Memories that were provided as context for this message
    public var recalledMemories: [Memory]?

    /// Documents that were provided as context for this message
    public var recalledDocuments: [DocumentContext]?
    
    /// Context used for subagent execution (if applicable)
    public var subagentContext: SubagentContext?
    
    /// For user messages: structured map of prompt sections (e.g. "system" -> content)
    public var structuredContext: [String: String]?
    
    /// Whether this message is a system summary/truncation notice
    public var isSummary: Bool
    
    /// Type of summary (if role is .summary)
    public var summaryType: SummaryType?

    /// Helper to get generated tags from debug info
    public var tags: [String]? {
        debugInfo?.generatedTags
    }
    
    public enum SummaryType: String, Codable, Sendable {
        case topic // Vertical line
        case broad // Middle blob
    }

    /// Helper to get generation stats from debug info
    public var stats: (tokensPerSecond: Double?, totalTokens: Int?)? {
        guard let apiResponse = debugInfo?.apiResponse else { return nil }
        return (apiResponse.tokensPerSecond, apiResponse.totalTokens)
    }

    public init(
        content: String, role: MessageRole, think: String? = nil, toolCalls: [ToolCall]? = nil,
        debugInfo: MessageDebugInfo? = nil,
        parentId: UUID? = nil,
        gatheringProgress: ContextGatheringProgress? = nil,
        recalledMemories: [Memory]? = nil,
        recalledDocuments: [DocumentContext]? = nil,
        subagentContext: SubagentContext? = nil,
        isSummary: Bool = false,
        summaryType: SummaryType? = nil
    ) {
        self.content = content
        self.role = role
        self.think = think
        self.toolCalls = toolCalls
        self.debugInfo = debugInfo
        self.parentId = parentId
        self.gatheringProgress = gatheringProgress
        self.recalledMemories = recalledMemories
        self.recalledDocuments = recalledDocuments
        self.subagentContext = subagentContext
        self.isSummary = isSummary
        self.summaryType = summaryType
    }

    public enum MessageRole: String, Sendable {
        case user
        case assistant
        case system
        case tool
        case summary
    }

    public enum ContextGatheringProgress: String, Sendable, CaseIterable {
        case augmenting = "Augmenting Query"
        case tagging = "Generating Tags"
        case embedding = "Generating Embedding"
        case searching = "Searching Memories"
        case ranking = "Ranking Results"
        case complete = "Context Ready"
    }

    /// Content cleaned for UI display (removes <tool_call> tags)
    public var displayContent: String {
        // Pattern to match <tool_call>...</tool_call> tags, optionally wrapped in code blocks
        let pattern = "(?:```(?:xml)?\\s*)?<tool_call>(.*?)</tool_call>(?:\\s*```)?"

        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        else {
            return content
        }

        let nsString = content as NSString
        return regex.stringByReplacingMatches(
            in: content,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Subagent Context

/// Context information for a subagent execution
public struct SubagentContext: Equatable, Sendable, Codable {
    public let prompt: String
    public let documents: [String] // Paths
    public let rawResponse: String? // Full output including thinking
    
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
public struct MessageDebugInfo: Equatable, Sendable {
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
public struct APIResponseMetadata: Equatable, Sendable {
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

// MARK: - Response Parsing

extension Message {
    /// Parse LLM response and extract thinking tags
    ///
    /// Extracts Chain of Thought reasoning from `<think>...</think>` blocks.
    /// Supported by models like:
    /// - DeepSeek R1
    /// - QwQ (Alibaba)
    /// - Other reasoning models
    ///
    /// Example input:
    /// ```
    /// <think>Let me break this down step by step...</think>
    /// The answer is 42.
    /// ```
    ///
    /// Example output:
    /// ```
    /// content: "The answer is 42."
    /// think: "Let me break this down step by step..."
    /// ```
    ///
    /// - Parameter rawResponse: Raw response from LLM
    /// - Returns: Tuple with content and optional thinking
    public static func parseResponse(_ rawResponse: String) -> (content: String, think: String?) {
        // Pattern to match <think>...</think> tags
        let pattern = "<think>(.*?)</think>"

        guard
            let regex = try? NSRegularExpression(
                pattern: pattern, options: .dotMatchesLineSeparators)
        else {
            return (rawResponse, nil)
        }

        let nsString = rawResponse as NSString
        let matches = regex.matches(
            in: rawResponse, range: NSRange(location: 0, length: nsString.length))

        // Extract thinking content
        var thinkingText: String?
        if let match = matches.first, match.numberOfRanges > 1 {
            let thinkRange = match.range(at: 1)
            thinkingText = nsString.substring(with: thinkRange).trimmingCharacters(
                in: .whitespacesAndNewlines)
        }

        // Remove all <think>...</think> blocks from content
        let cleanContent = regex.stringByReplacingMatches(
            in: rawResponse,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return (cleanContent, thinkingText)
    }
}
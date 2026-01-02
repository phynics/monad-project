import Foundation

/// UI message model for chat interface
///
/// Supports Chain of Thought (CoT) reasoning models that use `<think>` tags
/// to show their reasoning process separately from the final answer.
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

    public init(
        content: String, role: MessageRole, think: String? = nil, toolCalls: [ToolCall]? = nil,
        debugInfo: MessageDebugInfo? = nil
    ) {
        self.content = content
        self.role = role
        self.think = think
        self.toolCalls = toolCalls
        self.debugInfo = debugInfo
    }

    public enum MessageRole: String, Sendable {
        case user
        case assistant
        case system
        case tool
    }
}

// MARK: - Tool Call

/// Represents a tool call from the LLM
public struct ToolCall: Identifiable, Equatable, Codable, Sendable {
    public let id = UUID()
    public let name: String
    public let arguments: [String: String]

    public init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }

    public static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.name == rhs.name && lhs.arguments == rhs.arguments
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

    public static func userMessage(rawPrompt: String) -> MessageDebugInfo {
        MessageDebugInfo(
            rawPrompt: rawPrompt,
            apiResponse: nil,
            originalResponse: nil,
            parsedContent: nil,
            parsedThinking: nil,
            parsedToolCalls: nil
        )
    }

    public static func assistantMessage(
        response: APIResponseMetadata,
        original: String? = nil,
        parsed: String? = nil,
        thinking: String? = nil,
        toolCalls: [ToolCall]? = nil
    ) -> MessageDebugInfo {
        MessageDebugInfo(
            rawPrompt: nil,
            apiResponse: response,
            originalResponse: original,
            parsedContent: parsed,
            parsedThinking: thinking,
            parsedToolCalls: toolCalls
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

    public init(
        model: String? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil,
        totalTokens: Int? = nil, finishReason: String? = nil, systemFingerprint: String? = nil
    ) {
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.finishReason = finishReason
        self.systemFingerprint = systemFingerprint
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

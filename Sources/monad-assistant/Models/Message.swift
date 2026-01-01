import Foundation

/// UI message model for chat interface
///
/// Supports Chain of Thought (CoT) reasoning models that use `<think>` tags
/// to show their reasoning process separately from the final answer.
struct Message: Identifiable, Equatable {
    let id = UUID()

    /// The main response content (with <think> tags removed)
    let content: String

    let role: MessageRole
    let timestamp = Date()

    /// Chain of Thought reasoning extracted from <think>...</think> blocks
    /// Only present for models that support reasoning tags (e.g., DeepSeek R1, QwQ)
    let think: String?

    /// Tool calls extracted from <tool_call>...</tool_call> blocks
    let toolCalls: [ToolCall]?

    /// Debug info - not persisted
    var debugInfo: MessageDebugInfo?

    init(
        content: String, role: MessageRole, think: String? = nil, toolCalls: [ToolCall]? = nil,
        debugInfo: MessageDebugInfo? = nil
    ) {
        self.content = content
        self.role = role
        self.think = think
        self.toolCalls = toolCalls
        self.debugInfo = debugInfo
    }

    enum MessageRole: String {
        case user
        case assistant
        case system
        case tool
    }
}

// MARK: - Tool Call

/// Represents a tool call from the LLM
struct ToolCall: Identifiable, Equatable, Codable {
    let id = UUID()
    let name: String
    let arguments: [String: String]

    init(name: String, arguments: [String: String]) {
        self.name = name
        self.arguments = arguments
    }

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        lhs.name == rhs.name && lhs.arguments == rhs.arguments
    }
}

// MARK: - Debug Info

/// Debug information for messages (not persisted)
struct MessageDebugInfo: Equatable {
    /// For user messages: the full raw prompt sent to LLM (with context, notes, etc.)
    var rawPrompt: String?

    /// For assistant messages: OpenAI API response metadata
    var apiResponse: APIResponseMetadata?

    /// For assistant messages: original unparsed response from LLM
    var originalResponse: String?

    /// For assistant messages: parsed content (after removing <think> tags)
    var parsedContent: String?

    /// For assistant messages: parsed thinking block
    var parsedThinking: String?

    /// For assistant messages: parsed tool calls
    var parsedToolCalls: [ToolCall]?

    static func userMessage(rawPrompt: String) -> MessageDebugInfo {
        MessageDebugInfo(
            rawPrompt: rawPrompt,
            apiResponse: nil,
            originalResponse: nil,
            parsedContent: nil,
            parsedThinking: nil,
            parsedToolCalls: nil
        )
    }

    static func assistantMessage(
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
struct APIResponseMetadata: Equatable {
    var model: String?
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    var finishReason: String?
    var systemFingerprint: String?
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
    static func parseResponse(_ rawResponse: String) -> (content: String, think: String?) {
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

import Foundation

/// UI message model for chat interface
///
/// Supports Chain of Thought (CoT) reasoning models that use `<think>` tags
/// to show their reasoning process separately from the final answer.
public struct Message: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID

    /// The main response content (with <think> tags removed)
    public let content: String

    public let role: MessageRole
    public let timestamp: Date

    /// Chain of Thought reasoning extracted from <think>...</think> blocks
    /// Only present for models that support reasoning tags (e.g., DeepSeek R1, QwQ)
    public let think: String?

    /// Tool calls extracted from <tool_call>...</tool_call> blocks
    public let toolCalls: [ToolCall]?

    /// ID of the tool call this message is a response to (only for .tool role)
    public let toolCallId: String?

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
        case topic  // Vertical line
        case broad  // Middle blob
    }

    /// Helper to get generation stats from debug info
    public var stats: (tokensPerSecond: Double?, totalTokens: Int?)? {
        guard let apiResponse = debugInfo?.apiResponse else { return nil }
        return (apiResponse.tokensPerSecond, apiResponse.totalTokens)
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String, role: MessageRole, think: String? = nil, toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        debugInfo: MessageDebugInfo? = nil,
        parentId: UUID? = nil,
        gatheringProgress: ContextGatheringProgress? = nil,
        recalledMemories: [Memory]? = nil,
        recalledDocuments: [DocumentContext]? = nil,
        subagentContext: SubagentContext? = nil,
        isSummary: Bool = false,
        summaryType: SummaryType? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.role = role
        self.think = think
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.debugInfo = debugInfo
        self.parentId = parentId
        self.gatheringProgress = gatheringProgress
        self.recalledMemories = recalledMemories
        self.recalledDocuments = recalledDocuments
        self.subagentContext = subagentContext
        self.isSummary = isSummary
        self.summaryType = summaryType
    }

    public enum MessageRole: String, Sendable, Codable {
        case user
        case assistant
        case system
        case tool
        case summary
    }

    public enum ContextGatheringProgress: String, Sendable, Codable, CaseIterable {
        case augmenting = "Augmenting Query"
        case tagging = "Generating Tags"
        case embedding = "Generating Embedding"
        case searching = "Searching Memories"
        case ranking = "Ranking Results"
        case complete = "Context Ready"
    }

    /// Content cleaned for UI display (removes <tool_call> tags)
    public var displayContent: String {
        MessageParser.displayContent(for: content)
    }
}

// MARK: - Response Parsing

extension Message {
    /// Parse LLM response and extract thinking tags
    /// - Parameter rawResponse: Raw response from LLM
    /// - Returns: Tuple with content and optional thinking
    public static func parseResponse(_ rawResponse: String) -> (content: String, think: String?) {
        MessageParser.parseResponse(rawResponse)
    }
}

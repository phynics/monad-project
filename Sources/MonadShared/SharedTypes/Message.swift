import Foundation

/// UI message model for chat interface
///
/// Supports Chain of Thought (CoT) reasoning models that use `<think>` tags
/// to show their reasoning process separately from the final answer.
public struct Message: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID

    /// The main response content (with <think> tags removed)
    public var content: String

    public var role: MessageRole
    public let timestamp: Date

    /// Chain of Thought reasoning extracted from <think>...</think> blocks
    /// Only present for models that support reasoning tags (e.g., DeepSeek R1, QwQ)
    public var think: String?

    /// Tool calls extracted from <tool_call>...</tool_call> blocks
    public var toolCalls: [ToolCall]?

    /// ID of the tool call this message is a response to (only for .tool role)
    public var toolCallId: String?

    /// Optional ID of the parent message in the forest structure
    public var parentId: UUID?

    /// Memories that were provided as context for this message
    public var recalledMemories: [Memory]?

    /// Whether this message is a system summary/truncation notice
    public var isSummary: Bool

    /// Type of summary (if role is .summary)
    public var summaryType: SummaryType?

    public enum SummaryType: String, Codable, Sendable {
        case topic // Vertical line
        case broad // Middle blob
    }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String, role: MessageRole, think: String? = nil, toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        parentId: UUID? = nil,
        recalledMemories: [Memory]? = nil,
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
        self.parentId = parentId
        self.recalledMemories = recalledMemories
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

public extension Message {
    /// Parse LLM response and extract thinking tags
    /// - Parameter rawResponse: Raw response from LLM
    /// - Returns: Tuple with content and optional thinking
    static func parseResponse(_ rawResponse: String) -> (content: String, think: String?) {
        MessageParser.parseResponse(rawResponse)
    }
}

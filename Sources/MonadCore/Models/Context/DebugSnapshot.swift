import MonadShared
import Foundation

/// A snapshot of what was sent to the LLM for debuggging purposes
public struct DebugSnapshot: Codable, Sendable {
    /// When this exchange happened
    public let timestamp: Date

    /// The structured context sections that were assembled into the prompt
    /// Keys are section IDs like "system_instructions", "context_notes", "memories", "chat_history", "tools", "user_query"
    public let structuredContext: [String: String]

    /// Tool calls made during the ReAct loop
    public let toolCalls: [ToolCallRecord]

    /// Tool execution results
    public let toolResults: [ToolResultRecord]

    /// The LLM model used
    public let model: String

    /// Number of ReAct turns (1 = no tool calls, >1 = tool loop)
    public let turnCount: Int

    public init(
        timestamp: Date = Date(),
        structuredContext: [String: String],
        toolCalls: [ToolCallRecord] = [],
        toolResults: [ToolResultRecord] = [],
        model: String,
        turnCount: Int
    ) {
        self.timestamp = timestamp
        self.structuredContext = structuredContext
        self.toolCalls = toolCalls
        self.toolResults = toolResults
        self.model = model
        self.turnCount = turnCount
    }
}

/// Record of a tool call made during a chat exchange
public struct ToolCallRecord: Codable, Sendable {
    public let name: String
    public let arguments: String  // raw JSON string
    public let turn: Int

    public init(name: String, arguments: String, turn: Int) {
        self.name = name
        self.arguments = arguments
        self.turn = turn
    }
}

/// Record of a tool execution result
public struct ToolResultRecord: Codable, Sendable {
    public let toolCallId: String
    public let name: String
    public let output: String  // truncated if very large
    public let turn: Int

    public init(toolCallId: String, name: String, output: String, turn: Int) {
        self.toolCallId = toolCallId
        self.name = name
        self.output = output
        self.turn = turn
    }
}

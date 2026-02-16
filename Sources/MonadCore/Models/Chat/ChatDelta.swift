import MonadShared
import Foundation

/// A submission of a tool output
public struct ToolOutputSubmission: Codable, Sendable {
    public let toolCallId: String
    public let output: String

    public init(toolCallId: String, output: String) {
        self.toolCallId = toolCallId
        self.output = output
    }
}

/// A delta from a streaming chat response
public struct ChatDelta: Sendable, Codable {
    public let content: String?
    public let thought: String?
    public let toolCalls: [ToolCallDelta]?
    public let metadata: ChatMetadata?
    public let error: String?
    public let isDone: Bool

    public init(
        content: String? = nil,
        thought: String? = nil,
        toolCalls: [ToolCallDelta]? = nil,
        metadata: ChatMetadata? = nil,
        error: String? = nil,
        isDone: Bool = false
    ) {
        self.content = content
        self.thought = thought
        self.toolCalls = toolCalls
        self.metadata = metadata
        self.error = error
        self.isDone = isDone
    }
}

/// A delta for a tool call in a streaming response
public struct ToolCallDelta: Sendable, Codable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let arguments: String?

    public init(index: Int, id: String? = nil, name: String? = nil, arguments: String? = nil) {
        self.index = index
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Metadata about the context used for a chat response
public struct ChatMetadata: Sendable, Codable {
    public let memories: [UUID]
    public let files: [String]

    public init(memories: [UUID] = [], files: [String] = []) {
        self.memories = memories
        self.files = files
    }
}

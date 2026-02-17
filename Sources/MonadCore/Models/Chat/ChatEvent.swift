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

/// Events emitted by ChatEngine during a chat turn.
/// Reuses existing types: ToolCallDelta, ChatMetadata.
public enum ChatEvent: Sendable {
    /// Incremental content chunk from the LLM
    case delta(String)
    
    /// Chain-of-thought reasoning chunk
    case thought(String)
    
    /// Tool call being assembled (streaming deltas)
    case toolCall(ToolCallDelta)
    
    /// Tool finished executing
    case toolResult(name: String, output: String)
    
    /// RAG context metadata — emitted once at the start of the loop
    case metadata(ChatMetadata)
    
    /// Stream completed with final accumulated content
    case completion(String)
    
    /// Error occurred
    case error(String)
}

// MARK: - Convenience Properties

extension ChatEvent {
    /// Extract content from a `.delta` event
    public var content: String? {
        if case .delta(let c) = self { return c }
        return nil
    }
    
    /// Extract content from a `.completion` event
    public var completionContent: String? {
        if case .completion(let c) = self { return c }
        return nil
    }
    
    /// Whether this is a `.completion` event
    public var isCompletion: Bool {
        if case .completion = self { return true }
        return false
    }
    
    /// Whether this is an `.error` event
    public var isError: Bool {
        if case .error = self { return true }
        return false
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

import MonadShared
import Foundation

public enum ToolExecutionStatus: Sendable {
    case attempting(name: String, reference: ToolReference)
    case success(ToolResult)
    case failure(Error)
}

/// Events emitted by ChatEngine during a chat turn.
public enum ChatEvent: Sendable {
    /// RAG context metadata — emitted once at the start of the loop
    case generationContext(ChatMetadata)
    
    /// Incremental content chunk from the LLM
    case delta(String)
    
    /// Chain-of-thought reasoning chunk
    case thought(String)
    
    /// Chain-of-thought reasoning block finished
    case thoughtCompleted
    
    /// Tool call being assembled (streaming deltas)
    case toolCall(ToolCallDelta)
    
    /// Tool call failed before execution (e.g. not found, invalid arguments)
    case toolCallError(toolCallId: String, name: String, error: String)
    
    /// Asynchronous tool execution status Updates
    case toolExecution(toolCallId: String, status: ToolExecutionStatus)
    
    /// Stream completed with final accumulated message and token metadata
    case generationCompleted(message: Message, metadata: APIResponseMetadata)
    
    /// Error occurred
    case error(Error)
}

// MARK: - Convenience Properties

extension ChatEvent {
    public var generationContext: ChatMetadata? {
        if case .generationContext(let m) = self { return m }
        return nil
    }
    
    public var delta: String? {
        if case .delta(let s) = self { return s }
        return nil
    }
    
    public var thought: String? {
        if case .thought(let s) = self { return s }
        return nil
    }
    
    public var isThoughtCompleted: Bool {
        if case .thoughtCompleted = self { return true }
        return false
    }
    
    public var toolCall: ToolCallDelta? {
        if case .toolCall(let tc) = self { return tc }
        return nil
    }
    
    public var toolCallError: (toolCallId: String, name: String, error: String)? {
        if case .toolCallError(let id, let name, let error) = self { return (id, name, error) }
        return nil
    }
    
    public var toolExecution: (toolCallId: String, status: ToolExecutionStatus)? {
        if case .toolExecution(let id, let status) = self { return (id, status) }
        return nil
    }
    
    public var generationCompleted: (message: Message, metadata: APIResponseMetadata)? {
        if case .generationCompleted(let msg, let meta) = self { return (msg, meta) }
        return nil
    }
    
    public var error: Error? {
        if case .error(let e) = self { return e }
        return nil
    }
    
    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

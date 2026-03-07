import Foundation

public enum ToolExecutionStatus: Sendable, Codable {
    case attempting(name: String, reference: ToolReference)
    case success(ToolResult)
    case failed(reference: ToolReference, error: String)
    case failure(String)
}

/// Events emitted by ChatEngine during a chat turn.
///
/// Events are categorized into four groups:
/// - `delta`: Incremental streaming events (text, thinking, tool calls, tool progress)
/// - `meta`: Informational metadata events (context, generation info)
/// - `error`: Error events (tool errors, general errors)
/// - `completion`: Terminal events signaling final results
public enum ChatEvent: Sendable, Codable {
    public enum DeltaEvent: Sendable, Codable {
        /// Chain-of-thought reasoning chunk
        case thinking(String)
        /// Incremental content chunk from the LLM
        case generation(String)
        /// Tool call being assembled (streaming deltas)
        case toolCall(ToolCallDelta)

        /// Asynchronous tool execution status update (progress)
        case toolExecution(toolCallId: String, status: ToolExecutionStatus)
    }

    public enum MetaEvent: Sendable, Codable {
        /// RAG context metadata — emitted once at the start of the loop
        case generationContext(ChatMetadata)
        /// Generation completed with metadata (informational)
        case generationCompleted(message: Message, metadata: APIResponseMetadata)
    }

    public enum ErrorEvent: Sendable, Codable {
        /// Tool call failed before execution (e.g. not found, invalid arguments)
        case toolCallError(toolCallId: String, name: String, error: String)
        /// General error occurred
        case error(String)
        /// Generation was explicitly cancelled
        case generationCancelled
    }

    public enum CompletionEvent: Sendable, Codable {
        /// Stream completed with final accumulated message and token metadata
        case generationCompleted(message: Message, metadata: APIResponseMetadata)
        /// Tool execution completed with final status
        case toolExecution(toolCallId: String, status: ToolExecutionStatus)
        /// The entire stream is complete (terminal event)
        case streamCompleted
    }

    case delta(DeltaEvent)
    case meta(MetaEvent)
    case error(ErrorEvent)
    case completion(CompletionEvent)
}

// MARK: - Factory Methods (Producer Ergonomics)

public extension ChatEvent {
    /// Delta shortcuts
    static func thinking(_ text: String) -> ChatEvent {
        .delta(.thinking(text))
    }

    static func generation(_ text: String) -> ChatEvent {
        .delta(.generation(text))
    }

    static func toolCall(_ delta: ToolCallDelta) -> ChatEvent {
        .delta(.toolCall(delta))
    }

    static func toolProgress(toolCallId: String, status: ToolExecutionStatus) -> ChatEvent {
        .delta(.toolExecution(toolCallId: toolCallId, status: status))
    }

    /// Meta shortcuts
    static func generationContext(_ metadata: ChatMetadata) -> ChatEvent {
        .meta(.generationContext(metadata))
    }

    /// Error shortcuts
    static func toolCallError(toolCallId: String, name: String, error: String) -> ChatEvent {
        .error(.toolCallError(toolCallId: toolCallId, name: name, error: error))
    }

    static func error(_ err: Error) -> ChatEvent {
        .error(.error(err.localizedDescription))
    }

    static func error(_ msg: String) -> ChatEvent {
        .error(.error(msg))
    }

    static func generationCancelled() -> ChatEvent {
        .error(.generationCancelled)
    }

    /// Completion shortcuts
    static func generationCompleted(message: Message, metadata: APIResponseMetadata) -> ChatEvent {
        .completion(.generationCompleted(message: message, metadata: metadata))
    }

    static func toolCompleted(toolCallId: String, status: ToolExecutionStatus) -> ChatEvent {
        .completion(.toolExecution(toolCallId: toolCallId, status: status))
    }

    static func streamCompleted() -> ChatEvent {
        .completion(.streamCompleted)
    }
}

// MARK: - Computed Properties (Consumer Ergonomics)

public extension ChatEvent {
    /// The text content if this is a `.delta(.generation(...))` event.
    var textContent: String? {
        if case let .delta(.generation(text)) = self { return text }
        return nil
    }

    /// The thinking content if this is a `.delta(.thinking(...))` event.
    var thinkingContent: String? {
        if case let .delta(.thinking(text)) = self { return text }
        return nil
    }

    /// The completed message and metadata if this is a `.completion(.generationCompleted(...))` event.
    var completedMessage: (message: Message, metadata: APIResponseMetadata)? {
        if case let .completion(.generationCompleted(msg, meta)) = self { return (msg, meta) }
        return nil
    }
}

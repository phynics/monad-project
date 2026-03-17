import Dependencies
import Foundation
import MonadPrompt
import MonadShared

/// A high-level facade for `ChatEngine` that configures default dependencies internally.
public struct MonadChat: Sendable {
    private let llmService: any LLMServiceProtocol
    private let messageStore: any MessageStoreProtocol
    private var chatEngine = ChatEngine()

    /// Initializes a new `MonadChat` instance with the required dependencies.
    ///
    /// - Parameters:
    ///   - llmService: The LLM service to use for generation.
    ///   - messageStore: The store for persisting chat messages.
    public init(llmService: any LLMServiceProtocol, messageStore: any MessageStoreProtocol) {
        self.llmService = llmService
        self.messageStore = messageStore
    }

    /// Adds a custom stage to the chat execution pipeline.
    /// - Parameter stage: The custom pipeline stage to add.
    /// - Returns: A new instance of `MonadChat` with the stage added.
    public func addStage(_ stage: any PipelineStage<ChatTurnContext, ChatEvent>) -> MonadChat {
        var copy = self
        copy.chatEngine.additionalStages.append(stage)
        return copy
    }

    /// Execute a chat turn with default settings and no tools.
    /// - Parameters:
    ///   - timelineId: The unique identifier for the chat session.
    ///   - message: The user's input message.
    ///   - systemInstructions: Optional system instructions to override the default.
    ///   - agentInstanceId: Optional identifier for the agent instance.
    ///   - maxTurns: Maximum number of LLM turns before stopping. Defaults to 5.
    /// - Returns: An asynchronous stream of chat events.
    public func execute(
        timelineId: UUID,
        message: String,
        systemInstructions: String? = nil,
        agentInstanceId: UUID? = nil,
        maxTurns: Int = ChatEngine.Constants.defaultMaxTurns
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        try await execute(
            timelineId: timelineId,
            message: message,
            tools: [],
            toolOutputs: nil,
            contextManager: nil,
            systemInstructions: systemInstructions,
            agentInstanceId: agentInstanceId,
            maxTurns: maxTurns
        )
    }

    /// Execute a chat turn and return a stream of deltas.
    /// - Parameters:
    ///   - timelineId: The unique identifier for the chat session.
    ///   - message: The user's input message.
    ///   - tools: Pre-resolved tools available for this turn.
    ///   - toolOutputs: Optional list of tool outputs submitted by the client from a previous turn.
    ///   - contextManager: Optional context manager for RAG. If nil, no context is gathered.
    ///   - systemInstructions: Optional system instructions to override the default.
    ///   - agentInstanceId: Optional identifier for the agent instance.
    ///   - maxTurns: Maximum number of LLM turns before stopping. Defaults to 5.
    /// - Returns: An asynchronous stream of chat events.
    public func execute(
        timelineId: UUID,
        message: String,
        tools: [AnyTool],
        toolOutputs: [ToolOutputSubmission]? = nil,
        contextManager: ContextManager? = nil,
        systemInstructions: String? = nil,
        agentInstanceId: UUID? = nil,
        maxTurns: Int = ChatEngine.Constants.defaultMaxTurns
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        return try await withDependencies {
            $0.llmService = self.llmService
            $0.messageStore = self.messageStore
        } operation: {
            try await chatEngine.execute(
                timelineId: timelineId,
                message: message,
                tools: tools,
                toolOutputs: toolOutputs,
                contextManager: contextManager,
                systemInstructions: systemInstructions,
                agentInstanceId: agentInstanceId,
                maxTurns: maxTurns
            )
        }
    }
}
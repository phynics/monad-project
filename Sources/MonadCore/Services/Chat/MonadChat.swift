import Dependencies
import Foundation
import MonadPrompt
import MonadShared

/// The interface boundary for MonadCore's chat subsystem.
///
/// Accepts all required services as init parameters and injects them internally,
/// so consumers never interact with `swift-dependencies` directly.
public struct MonadCoreChat: Sendable {
    // MARK: - Direct ChatEngine dependencies

    private let llmService: any LLMServiceProtocol
    private let messageStore: any MessageStoreProtocol
    private let timelineManager: TimelineManager
    private let toolRouter: ToolRouter
    private let agentInstanceStore: any AgentInstanceStoreProtocol
    private let clientStore: any ClientStoreProtocol
    private let chatTurnPlugins: [any ChatTurnPlugin]

    // MARK: - Transitive dependencies (TimelineManager, ContextManager)

    private let timelinePersistence: any TimelinePersistenceProtocol
    private let workspacePersistence: any WorkspacePersistenceProtocol
    private let memoryStore: any MemoryStoreProtocol
    private let toolPersistence: any ToolPersistenceProtocol
    private let agentTemplateStore: any AgentTemplateStoreProtocol
    private let embeddingService: any EmbeddingServiceProtocol

    private var chatEngine = ChatEngine()

    // MARK: - Init

    /// Initializes with all services required by the chat subsystem.
    ///
    /// - Parameters:
    ///   - llmService: The LLM service to use for generation.
    ///   - messageStore: The store for persisting chat messages.
    ///   - timelineManager: Manages timeline state, workspaces, and extensions.
    ///   - toolRouter: Routes tool calls to the appropriate executor.
    ///   - agentInstanceStore: Persistence for agent instance data.
    ///   - clientStore: Persistence for client identity data.
    ///   - timelinePersistence: Persistence for timeline records.
    ///   - workspacePersistence: Persistence for workspace records.
    ///   - memoryStore: Persistence for memory records.
    ///   - toolPersistence: Persistence for tool references.
    ///   - agentTemplateStore: Persistence for agent templates.
    ///   - embeddingService: Embedding provider for context/memory search.
    ///   - chatTurnPlugins: Post-turn plugins (e.g. autonomous reactions). Defaults to none.
    public init(
        llmService: any LLMServiceProtocol,
        messageStore: any MessageStoreProtocol,
        timelineManager: TimelineManager,
        toolRouter: ToolRouter,
        agentInstanceStore: any AgentInstanceStoreProtocol,
        clientStore: any ClientStoreProtocol,
        timelinePersistence: any TimelinePersistenceProtocol,
        workspacePersistence: any WorkspacePersistenceProtocol,
        memoryStore: any MemoryStoreProtocol,
        toolPersistence: any ToolPersistenceProtocol,
        agentTemplateStore: any AgentTemplateStoreProtocol,
        embeddingService: any EmbeddingServiceProtocol,
        chatTurnPlugins: [any ChatTurnPlugin] = []
    ) {
        self.llmService = llmService
        self.messageStore = messageStore
        self.timelineManager = timelineManager
        self.toolRouter = toolRouter
        self.agentInstanceStore = agentInstanceStore
        self.clientStore = clientStore
        self.timelinePersistence = timelinePersistence
        self.workspacePersistence = workspacePersistence
        self.memoryStore = memoryStore
        self.toolPersistence = toolPersistence
        self.agentTemplateStore = agentTemplateStore
        self.embeddingService = embeddingService
        self.chatTurnPlugins = chatTurnPlugins
    }

    // MARK: - Builder

    /// Adds a custom stage to the chat execution pipeline.
    /// - Parameter stage: The custom pipeline stage to add.
    /// - Returns: A new instance of `MonadCoreChat` with the stage added.
    public func addStage(_ stage: any PipelineStage<ChatTurnContext, ChatEvent>) -> MonadCoreChat {
        var copy = self
        copy.chatEngine.additionalStages.append(stage)
        return copy
    }

    // MARK: - Execution

    /// Run a chat turn and return a stream of events.
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
    public func run(
        timelineId: UUID,
        message: String,
        tools: [AnyTool] = [],
        toolOutputs: [ToolOutputSubmission]? = nil,
        contextManager: ContextManager? = nil,
        systemInstructions: String? = nil,
        agentInstanceId: UUID? = nil,
        maxTurns: Int = ChatEngine.Constants.defaultMaxTurns
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        try await withDependencies {
            // Direct ChatEngine deps
            $0.llmService = self.llmService
            $0.messageStore = self.messageStore
            $0.timelineManager = self.timelineManager
            $0.toolRouter = self.toolRouter
            $0.agentInstanceStore = self.agentInstanceStore
            $0.clientStore = self.clientStore
            $0.chatTurnPlugins = self.chatTurnPlugins
            // Transitive deps
            $0.timelinePersistence = self.timelinePersistence
            $0.workspacePersistence = self.workspacePersistence
            $0.memoryStore = self.memoryStore
            $0.toolPersistence = self.toolPersistence
            $0.agentTemplateStore = self.agentTemplateStore
            $0.embeddingService = self.embeddingService
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

import MonadCore
import OSLog
import Observation
import OpenAI
import SwiftUI

@MainActor
@Observable
public final class ChatViewModel {
    // MARK: - State Properties
    public var inputText: String = ""
    public var messages: [Message] = []
    public var activeMemories: [ActiveMemory] = []
    public var isLoading = false
    public var isExecutingTools = false
    public var errorMessage: String?
    public var performanceMetrics = PerformanceMetrics()
    public var shouldInjectLongContext = false

    /// When enabled, automatically dequeues and processes the next job when chat awaits user input
    public var autoDequeueEnabled = false

    // MARK: - Service Dependencies
    public let llmService: LLMService
    public let persistenceManager: PersistenceManager
    public let contextManager: ContextManager
    public let documentManager: DocumentManager
    public let streamingCoordinator: StreamingCoordinator
    public let conversationArchiver: ConversationArchiver
    public let contextCompressor: ContextCompressor

    // MARK: - Tool Infrastructure (owned by ChatViewModel)
    public let jobQueueContext: JobQueueContext
    public let toolContextSession: ToolContextSession

    /// Tool manager - lazily initialized via computed property
    private var _toolManager: SessionToolManager?
    public var toolManager: SessionToolManager {
        if let existing = _toolManager, !_toolsNeedRecreation {
            return existing
        }
        let manager = createToolManager()
        _toolManager = manager
        _toolsNeedRecreation = false
        return manager
    }

    /// Tool executor - lazily initialized via computed property
    private var _toolExecutor: ToolExecutor?
    public var toolExecutor: ToolExecutor {
        if let existing = _toolExecutor, !_toolsNeedRecreation {
            return existing
        }
        let executor = createToolExecutor()
        _toolExecutor = executor
        return executor
    }

    /// Flag to force tool infrastructure recreation (e.g., after directory change)
    private var _toolsNeedRecreation = false

    // MARK: - Internal Storage
    internal var currentTask: Task<Void, Never>?
    internal let logger = Logger.chat

    // MARK: - Computed Properties
    public var injectedMemories: [Memory] {
        let pinned = activeMemories.filter { $0.isPinned }
        let unpinned = activeMemories.filter { !$0.isPinned }
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .prefix(5)

        return (pinned + Array(unpinned)).map { $0.memory }
    }

    public var injectedDocuments: [DocumentContext] {
        var docs = documentManager.getEffectiveDocuments(
            limit: llmService.configuration.documentContextLimit)

        if shouldInjectLongContext {
            let longText = String(
                repeating: "This is a long context placeholder for performance testing. ",
                count: 1000)
            let longDoc = DocumentContext(
                path: "performance_test_long_context.txt", content: longText)
            docs.append(longDoc)
        }

        return docs
    }

    // Expose streaming state
    public var streamingThinking: String {
        streamingCoordinator.streamingThinking
    }

    public var streamingContent: String {
        streamingCoordinator.streamingContent
    }

    public var isStreaming: Bool {
        streamingCoordinator.isStreaming
    }

    // MARK: - Initialization
    public init(llmService: LLMService, persistenceManager: PersistenceManager) {
        self.llmService = llmService
        self.persistenceManager = persistenceManager
        self.contextManager = ContextManager(
            persistenceService: persistenceManager.persistence,
            embeddingService: llmService.embeddingService
        )
        self.documentManager = DocumentManager()
        self.streamingCoordinator = StreamingCoordinator()
        self.conversationArchiver = ConversationArchiver(
            persistence: persistenceManager.persistence,
            llmService: llmService,
            contextManager: contextManager
        )
        self.contextCompressor = ContextCompressor(llmService: llmService)

        // Initialize tool infrastructure
        self.jobQueueContext = JobQueueContext()
        self.toolContextSession = ToolContextSession()

        Task {
            await checkStartupState()
        }
    }

    // MARK: - Tool Infrastructure Management

    /// Invalidates tool infrastructure to force recreation with new working directory
    public func invalidateToolInfrastructure() {
        _toolsNeedRecreation = true
        _toolManager = nil
        _toolExecutor = nil
    }
}

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
    public var jobs: [Job] = []
    public var isLoading = false
    public var isExecutingTools = false
    public var errorMessage: String?
    public var performanceMetrics = PerformanceMetrics()
    
    // SQL Confirmation Proxy State
    public var pendingSQLOperation: (sql: String, onConfirm: @MainActor () -> Void, onCancel: @MainActor () -> Void)?
    public var showSQLConfirmation = false

    /// When enabled, automatically dequeues and processes the next job when chat awaits user input
    public var autoDequeueEnabled = false

    // MARK: - Service Dependencies
    public let llmService: LLMService
    public let llmManager: LLMManager // UI Wrapper
    
    public let persistenceManager: PersistenceManager
    public let contextManager: ContextManager
    
    public let documentManager: DocumentManager
    public let documentUIManager: DocumentUIManager // UI Wrapper
    
    public let streamingCoordinator: StreamingCoordinator
    public let conversationArchiver: ConversationArchiver
    public let contextCompressor: ContextCompressor
    public let toolContextSession: ToolContextSession
    public let jobQueueContext: JobQueueContext
    
    public var toolOrchestrator: ToolOrchestrator!
    public var sessionOrchestrator: SessionOrchestrator!
    public var maintenanceOrchestrator: MaintenanceOrchestrator!

    // MARK: - Cached State for UI
    public private(set) var injectedDocuments: [DocumentContext] = []
    public private(set) var enabledTools: [any MonadCore.Tool] = []

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
    
    private var _toolUIManager: ToolUIManager?
    public var toolUIManager: ToolUIManager {
        if let existing = _toolUIManager, !_toolsNeedRecreation {
            return existing
        }
        let manager = ToolUIManager(manager: toolManager)
        _toolUIManager = manager
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
        self.llmManager = LLMManager(service: llmService)
        
        self.persistenceManager = persistenceManager
        self.contextManager = ContextManager(
            persistenceService: persistenceManager.persistence,
            embeddingService: llmService.embeddingService
        )
        self.documentManager = DocumentManager()
        self.documentUIManager = DocumentUIManager(manager: documentManager)
        
        self.streamingCoordinator = StreamingCoordinator()
        self.conversationArchiver = ConversationArchiver(
            persistence: persistenceManager.persistence,
            llmService: llmService,
            contextManager: contextManager
        )
        self.contextCompressor = ContextCompressor(llmService: llmService)

        // Initialize tool infrastructure
        self.jobQueueContext = JobQueueContext(persistenceService: persistenceManager.persistence)
        self.toolContextSession = ToolContextSession()
        
        self.sessionOrchestrator = SessionOrchestrator(
            persistenceManager: persistenceManager,
            llmService: llmService
        )
        self.maintenanceOrchestrator = MaintenanceOrchestrator(
            contextCompressor: contextCompressor,
            persistenceManager: persistenceManager
        )
        
        // Setup ToolOrchestrator (needs toolExecutor which is created lazily)
        self.toolOrchestrator = ToolOrchestrator(
            toolExecutor: self.toolExecutor,
            persistenceManager: persistenceManager,
            jobQueueContext: jobQueueContext
        )
        self.toolOrchestrator.delegate = self

        Task {
            await checkStartupState()
            await refreshUIState()
        }
    }

    // MARK: - Tool Infrastructure Management

    /// Invalidates tool infrastructure to force recreation with new working directory
    public func invalidateToolInfrastructure() {
        _toolsNeedRecreation = true
        _toolManager = nil
        _toolUIManager = nil
        _toolExecutor = nil
        Task {
            await refreshUIState()
        }
    }

    public func refreshJobs() async {
        do {
            self.jobs = try await jobQueueContext.listJobs()
        } catch {
            logger.error("Failed to refresh jobs: \(error.localizedDescription)")
        }
    }
    
    public func refreshUIState() async {
        let docs = await documentManager.getEffectiveDocuments(limit: await llmService.configuration.memoryContextLimit) // Fixed limit param
        let tools = await toolManager.getEnabledTools()
        
        await MainActor.run {
            self.injectedDocuments = docs
            self.enabledTools = tools
        }
    }

    internal func handleCancellation() {
        logger.notice("Generation cancelled by user")
        if !streamingCoordinator.streamingContent.isEmpty {
            let assistantMessage = Message(
                content: streamingCoordinator.streamingContent + "\n\n[Generation cancelled]",
                role: .assistant,
                think: streamingCoordinator.streamingThinking.isEmpty ? nil : streamingCoordinator.streamingThinking
            )
            messages.append(assistantMessage)
        }
        streamingCoordinator.stopStreaming()
        currentTask = nil
        isLoading = false
    }

    public func cancelGeneration() {
        currentTask?.cancel()
        currentTask = nil
    }
}

// MARK: - SQL Confirmation Proxy

extension ChatViewModel: SQLConfirmationDelegate {
    public func requestConfirmation(for sql: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            self.pendingSQLOperation = (
                sql: sql,
                onConfirm: {
                    self.showSQLConfirmation = false
                    self.pendingSQLOperation = nil
                    continuation.resume(returning: true)
                },
                onCancel: {
                    self.showSQLConfirmation = false
                    self.pendingSQLOperation = nil
                    continuation.resume(returning: false)
                }
            )
            self.showSQLConfirmation = true
        }
    }
}

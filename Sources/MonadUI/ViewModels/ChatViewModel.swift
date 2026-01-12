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
    public var llmService: any LLMServiceProtocol { coordinator.activeLLMService }
    public var persistenceManager: PersistenceManager
    public var contextManager: ContextManager
    public let documentManager: DocumentManager
    public let streamingCoordinator: StreamingCoordinator
    public let conversationArchiver: ConversationArchiver
    public let contextCompressor: ContextCompressor
    
    public var toolOrchestrator: ToolOrchestrator!
    public var sessionOrchestrator: SessionOrchestrator!
    public var maintenanceOrchestrator: MaintenanceOrchestrator!

    internal let coordinator: ServiceCoordinator

    // MARK: - Tool Infrastructure (owned by ChatViewModel)
    public var jobQueueContext: JobQueueContext
    public var toolContextSession: ToolContextSession

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
        documentManager.getEffectiveDocuments(
            limit: (llmService.configuration.documentContextLimit))
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
        self.persistenceManager = persistenceManager
        
        // 1. Stored properties
        self.jobQueueContext = JobQueueContext(persistenceService: persistenceManager.persistence)
        self.toolContextSession = ToolContextSession()
        self.documentManager = DocumentManager()
        self.streamingCoordinator = StreamingCoordinator()
        
        self.coordinator = ServiceCoordinator(localLLM: llmService, localPersistence: persistenceManager.persistence as! PersistenceService)
        
        // 2. Initialize contextManager
        let contextManager = ContextManager(
            persistenceService: persistenceManager.persistence,
            embeddingService: llmService.embeddingService
        )
        self.contextManager = contextManager
        
        // 3. Initialize properties that depend on contextManager
        self.conversationArchiver = ConversationArchiver(
            persistence: persistenceManager.persistence,
            llmService: llmService,
            contextManager: contextManager
        )
        self.contextCompressor = ContextCompressor(llmService: llmService)

        // 4. Initialize orchestrators (late-init)
        self.sessionOrchestrator = SessionOrchestrator(
            persistenceManager: persistenceManager,
            llmService: llmService
        )
        self.maintenanceOrchestrator = MaintenanceOrchestrator(
            contextCompressor: self.contextCompressor,
            persistenceManager: persistenceManager
        )
        
        // 5. Setup tool orchestrator
        self.toolOrchestrator = ToolOrchestrator(
            toolExecutor: self.toolExecutor,
            persistenceManager: persistenceManager,
            jobQueueContext: jobQueueContext
        )
        self.toolOrchestrator.delegate = self
    }
    
    /// Initialize the view model state and services.
    /// Should be called after init.
    public func startup() async {
        // Apply current connection mode from config
        try? await coordinator.update(with: llmService.configuration)
        await checkStartupState()
    }

    // MARK: - Tool Infrastructure Management

    /// Invalidates tool infrastructure to force recreation with new working directory
    public func invalidateToolInfrastructure() {
        _toolsNeedRecreation = true
        _toolManager = nil
        _toolExecutor = nil
    }

    public func refreshJobs() async {
        do {
            self.jobs = try await jobQueueContext.listJobs()
        } catch {
            logger.error("Failed to refresh jobs: \(error.localizedDescription)")
        }
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

import OSLog
import Observation
import OpenAI
import SwiftUI
import MonadCore

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
    
    // MARK: - Service Dependencies
    public let llmService: LLMService
    public let persistenceManager: PersistenceManager
    public let contextManager: ContextManager
    public let documentManager: DocumentManager
    public let streamingCoordinator: StreamingCoordinator
    public let conversationArchiver: ConversationArchiver
    public var toolExecutor: ToolExecutor?

    // MARK: - Internal Storage
    internal var currentTask: Task<Void, Never>?
    internal var toolManager: SessionToolManager?
    internal let logger = Logger.chat
    
    // MARK: - Computed Properties
    public var injectedMemories: [Memory] {
        let pinned = activeMemories.filter { $0.isPinned }
        let unpinned = activeMemories.filter { !$0.isPinned }
            .sorted { $0.lastAccessed > $1.lastAccessed }
            .prefix(llmService.configuration.memoryContextLimit)
        
        return (pinned + Array(unpinned)).map { $0.memory }
    }
    
    public var injectedDocuments: [DocumentContext] {
        return documentManager.getEffectiveDocuments(limit: llmService.configuration.documentContextLimit)
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
            persistenceManager: persistenceManager,
            llmService: llmService,
            contextManager: contextManager
        )
        
        Task {
            await checkStartupState()
        }
    }

    // MARK: - Internal Helpers
    internal func setToolManager(_ manager: SessionToolManager) {
        self.toolManager = manager
    }
}

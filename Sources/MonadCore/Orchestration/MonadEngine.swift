import Foundation
import Logging

/// Central coordinator for the MonadCore framework
public final class MonadEngine: Sendable {
    public let persistenceService: any PersistenceServiceProtocol
    public let embeddingService: any EmbeddingServiceProtocol
    public let vectorStore: (any VectorStoreProtocol)?
    public let llmService: any LLMServiceProtocol
    
    public let sessionManager: SessionManager
    public let agentRegistry: AgentRegistry
    public let workspaceStore: WorkspaceStore
    public let toolRouter: ToolRouter
    public let chatOrchestrator: ChatOrchestrator
    
    public let jobRunner: JobRunnerService
    public let orphanCleanup: OrphanCleanupService
    
    private let logger = Logger(label: "com.monad.engine")
    
    public init(
        persistenceService: any PersistenceServiceProtocol,
        embeddingService: any EmbeddingServiceProtocol,
        vectorStore: (any VectorStoreProtocol)? = nil,
        llmService: any LLMServiceProtocol,
        workspaceRoot: URL,
        connectionManager: (any ClientConnectionManagerProtocol)? = nil
    ) async throws {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        self.llmService = llmService
        
        self.workspaceStore = try await WorkspaceStore(dbWriter: persistenceService.databaseWriter)
        self.agentRegistry = AgentRegistry()
        
        self.sessionManager = SessionManager(
            persistenceService: persistenceService,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            llmService: llmService,
            agentRegistry: agentRegistry,
            workspaceRoot: workspaceRoot,
            connectionManager: connectionManager
        )

        self.toolRouter = ToolRouter(sessionManager: sessionManager)
        self.chatOrchestrator = ChatOrchestrator(
            sessionManager: sessionManager,
            llmService: llmService,
            agentRegistry: agentRegistry,
            toolRouter: toolRouter
        )
        
        self.jobRunner = JobRunnerService(
            sessionManager: sessionManager,
            llmService: llmService,
            agentRegistry: agentRegistry
        )
        
        self.orphanCleanup = OrphanCleanupService(
            persistenceService: persistenceService,
            workspaceRoot: workspaceRoot,
            logger: Logger(label: "com.monad.orphan-cleanup")
        )
        
        logger.info("MonadEngine initialized.")
    }
    
    /// Start all background services
    public func start() async throws {
        // In a real implementation, we might want to return these as a list of tasks
        // or have a more robust lifecycle management.
        // For now, implementations (like MonadServer) can use the services individually.
    }
}

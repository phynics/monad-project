import Foundation
import Logging
import Dependencies
import ServiceLifecycle

/// Configuration for the MonadEngine
public struct MonadEngineConfiguration: Sendable {
    public let persistenceService: any PersistenceServiceProtocol
    public let embeddingService: any EmbeddingServiceProtocol
    public let vectorStore: (any VectorStoreProtocol)?
    public let llmService: any LLMServiceProtocol
    public let workspaceRoot: URL
    public let connectionManager: (any ClientConnectionManagerProtocol)?
    
    public init(
        persistenceService: any PersistenceServiceProtocol,
        embeddingService: any EmbeddingServiceProtocol,
        llmService: any LLMServiceProtocol,
        workspaceRoot: URL,
        vectorStore: (any VectorStoreProtocol)? = nil,
        connectionManager: (any ClientConnectionManagerProtocol)? = nil
    ) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
        self.llmService = llmService
        self.workspaceRoot = workspaceRoot
        self.vectorStore = vectorStore
        self.connectionManager = connectionManager
    }
}

/// Central coordinator for the MonadCore framework
public final class MonadEngine: Service, Sendable {
    public let configuration: MonadEngineConfiguration
    
    public var persistenceService: any PersistenceServiceProtocol { configuration.persistenceService }
    public var embeddingService: any EmbeddingServiceProtocol { configuration.embeddingService }
    public var vectorStore: (any VectorStoreProtocol)? { configuration.vectorStore }
    public var llmService: any LLMServiceProtocol { configuration.llmService }
    
    public let sessionManager: SessionManager
    public let agentRegistry: AgentRegistry
    public let workspaceStore: WorkspaceStore
    public let toolRouter: ToolRouter
    public let chatOrchestrator: ChatOrchestrator
    
    public let jobRunner: JobRunnerService
    public let orphanCleanup: OrphanCleanupService
    
    private let logger = Logger(label: "com.monad.engine")
    
    public init(configuration: MonadEngineConfiguration) async throws {
        self.configuration = configuration
        
        self.workspaceStore = try await WorkspaceStore(dbWriter: configuration.persistenceService.databaseWriter)
        self.agentRegistry = AgentRegistry()
        
        self.sessionManager = SessionManager(
            persistenceService: configuration.persistenceService,
            embeddingService: configuration.embeddingService,
            vectorStore: configuration.vectorStore,
            llmService: configuration.llmService,
            agentRegistry: agentRegistry,
            workspaceRoot: configuration.workspaceRoot,
            connectionManager: configuration.connectionManager
        )

        self.toolRouter = ToolRouter(sessionManager: sessionManager)
        self.chatOrchestrator = ChatOrchestrator(
            sessionManager: sessionManager,
            llmService: configuration.llmService,
            agentRegistry: agentRegistry,
            toolRouter: toolRouter
        )
        
        self.jobRunner = JobRunnerService(
            sessionManager: sessionManager,
            llmService: configuration.llmService,
            agentRegistry: agentRegistry
        )
        
        self.orphanCleanup = OrphanCleanupService(
            persistenceService: configuration.persistenceService,
            workspaceRoot: configuration.workspaceRoot,
            logger: Logger(label: "com.monad.orphan-cleanup")
        )
        
        logger.info("MonadEngine initialized.")
    }
    
    /// Convenience initializer for component-wise setup
    public convenience init(
        persistenceService: any PersistenceServiceProtocol,
        embeddingService: any EmbeddingServiceProtocol,
        vectorStore: (any VectorStoreProtocol)? = nil,
        llmService: any LLMServiceProtocol,
        workspaceRoot: URL,
        connectionManager: (any ClientConnectionManagerProtocol)? = nil
    ) async throws {
        let config = MonadEngineConfiguration(
            persistenceService: persistenceService,
            embeddingService: embeddingService,
            llmService: llmService,
            workspaceRoot: workspaceRoot,
            vectorStore: vectorStore,
            connectionManager: connectionManager
        )
        try await self.init(configuration: config)
    }
    
    /// Execute an operation with the engine's dependencies injected
    public func withDependencies<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await Dependencies.withDependencies {
            $0.withEngine(self)
        } operation: {
            try await operation()
        }
    }
    
    /// Start all background services
    public func start() async throws {
        logger.info("Starting MonadEngine services...")
        
        try await withDependencies {
            // Register default agents if needed
            if await !self.agentRegistry.hasAgent(id: "default") {
                let defaultAgent = AutonomousAgent(
                    manifest: AgentManifest(
                        id: "default",
                        name: "Default Agent",
                        description: "The default general-purpose agent.",
                        capabilities: ["general", "tool-use"]
                    )
                )
                await self.agentRegistry.register(defaultAgent)
            }
            
            if await !self.agentRegistry.hasAgent(id: "coordinator") {
                let coordinator = AgentCoordinator()
                await self.agentRegistry.register(coordinator)
            }
            
            // Start Job Runner
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.jobRunner.run()
                }
                
                // Add other services here
                // group.addTask { try await self.orphanCleanup.run() }
                
                // Wait for all services (they shouldn't exit unless cancelled)
                try await group.waitForAll()
            }
        }
    }
    
    /// Conformance to ServiceLifecycle.Service
    public func run() async throws {
        try await start()
    }
}

import Foundation
import Hummingbird
import Logging
import MonadCore
import MonadShared
import ServiceLifecycle
import UnixSignals
import HummingbirdWebSocket
import Dependencies

@available(macOS 14.0, *)
public struct MonadServerFactory {
    public typealias AppRequestContext = BasicWebSocketRequestContext

    public struct ServerContext {
        public let serviceGroup: ServiceGroup
        public let dependencies: DependencyValues
    }

    public static func createServerContext(
        hostname: String = "127.0.0.1",
        port: Int = 8080,
        verbose: Bool = false,
        logger: Logger = Logger.module(named: "server")
    ) async throws -> ServerContext {
        // Initialize Persistence
        let persistenceService: PersistenceService
        do {
            persistenceService = try PersistenceService.create()
            logger.info("Persistence initialized.")
        } catch {
            logger.error("Failed to initialize persistence: \(error)")
            throw error
        }

        let router = Router(context: AppRequestContext.self)

        // Add Global Middleware
        router.add(middleware: LogMiddleware())
        router.add(middleware: ErrorMiddleware())

        // Initialize Embedding Service
        let embeddingService: any EmbeddingServiceProtocol
        if let apiKey = ProcessInfo.processInfo.environment["MONAD_OPENAI_API_KEY"] ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty {
            embeddingService = OpenAIEmbeddingService(apiKey: apiKey)
            logger.info("Using OpenAI Embedding Service")
        } else {
            embeddingService = LocalEmbeddingService()
            logger.info("Using Local Embedding Service (OpenAI API Key not found)")
        }

        // Initialize Vector Store
        var vectorStore: any VectorStoreProtocol
        do {
            vectorStore = try VectorStore()
            try await vectorStore.initialize()
            logger.info("Vector Store initialized.")
        } catch {
            logger.error("Failed to initialize Vector Store: \(error). Falling back to mock.")
            vectorStore = MockVectorStore()
        }

        // Initialize LLM Service
        let appSupportDir = try defaultWorkspacePath().deletingLastPathComponent()
        let configURL = appSupportDir.appendingPathComponent("config.json")
        let storage = ConfigurationStorage(configURL: configURL)
        await storage.migrateIfNeeded()
        let llmService = ServerLLMService(storage: storage)
        await llmService.loadConfiguration()

        let workspaceRoot = try defaultWorkspacePath()

        // Initialize WebSocket Manager
        let connectionManager = WebSocketConnectionManager()

        // Initialize Core Services
        let agentRegistry = AgentRegistry()
        let sessionManager = SessionManager(
            workspaceRoot: workspaceRoot,
            connectionManager: connectionManager,
            workspaceCreator: WorkspaceFactory()
        )

        let toolRouter = ToolRouter()
        let chatEngine = ChatEngine()
        let agentExecutor = AgentExecutor(
            persistenceService: persistenceService,
            chatEngine: chatEngine
        )
        let jobRunner = JobRunnerService(
            sessionManager: sessionManager,
            agentRegistry: agentRegistry,
            agentExecutor: agentExecutor
        )
        let orphanCleanup = OrphanCleanupService(
            workspaceRoot: workspaceRoot,
            persistenceService: persistenceService
        )

        return try await withDependencies {
            $0.persistenceService = persistenceService
            $0.llmService = llmService
            $0.embeddingService = embeddingService
            $0.vectorStore = vectorStore
            $0.agentRegistry = agentRegistry
            $0.sessionManager = sessionManager
            $0.toolRouter = toolRouter
            $0.chatEngine = chatEngine
            $0.agentExecutor = agentExecutor
        } operation: {
            // Public routes
            router.get("/health") { _, _ -> String in
                return "OK"
            }

            let startTime = Date()
            let statusController = StatusAPIController<AppRequestContext>(
                persistenceService: persistenceService,
                llmService: llmService,
                startTime: startTime
            )
            statusController.addRoutes(to: router)

            router.get("/") { _, _ -> String in
                return "Monad Server is running."
            }

            // API Key from environment or default
            let apiKey = ProcessInfo.processInfo.environment["MONAD_API_KEY"] ?? "monad-secret"

            // Protected routes
            let protected = router.group("/api")
                .add(middleware: AuthMiddleware(token: apiKey))

            // WebSocket Route (Protected)
            let wsController = WebSocketAPIController<AppRequestContext>(connectionManager: connectionManager)
            wsController.addRoutes(to: protected)

            protected.get("/test") { _, _ -> String in
                return "Authenticated!"
            }

            let sessionController = SessionAPIController<AppRequestContext>(
                sessionManager: sessionManager)
            sessionController.addRoutes(to: protected.group("/sessions"))

            let chatController = ChatAPIController<AppRequestContext>(
                sessionManager: sessionManager,
                chatEngine: chatEngine,
                toolRouter: toolRouter,
                verbose: verbose
            )
            chatController.addRoutes(to: protected.group("/sessions"))

            let jobController = JobAPIController<AppRequestContext>(sessionManager: sessionManager)
            jobController.addRoutes(to: protected.group("/sessions"))

            let memoryController = MemoryAPIController<AppRequestContext>(sessionManager: sessionManager)
            memoryController.addRoutes(to: protected.group("/memories"))

            let pruneController = PruneAPIController<AppRequestContext>(
                persistenceService: persistenceService)
            pruneController.addRoutes(to: protected.group("/prune"))

            let toolController = ToolAPIController<AppRequestContext>(
                sessionManager: sessionManager,
                toolRouter: toolRouter
            )
            toolController.addRoutes(to: protected.group("/tools"))

            let agentController = AgentAPIController<AppRequestContext>(
                agentRegistry: agentRegistry
            )
            agentController.addRoutes(to: protected.group("/agents"))

            let workspacesGroup = protected.group("/workspaces")

            let workspaceAPIController = WorkspaceAPIController<AppRequestContext>(
                persistenceService: persistenceService, logger: logger)
            workspaceAPIController.addRoutes(to: workspacesGroup)

            let workspaceStore = try await WorkspaceStore(
                persistenceService: persistenceService,
                workspaceCreator: WorkspaceFactory()
            )
            let filesController = FilesAPIController<AppRequestContext>(
                workspaceStore: workspaceStore)
            filesController.addRoutes(to: protected.group("/workspaces/:workspaceId/files"))

            let clientController = ClientAPIController<AppRequestContext>(
                persistenceService: persistenceService, logger: logger)
            clientController.addRoutes(to: protected.group("/clients"))

            let configController = ConfigurationAPIController<AppRequestContext>(llmService: llmService)
            configController.addRoutes(to: protected.group("/config"))

            let app = Application(
                router: router,
                server: .http1WebSocketUpgrade(webSocketRouter: router, configuration: .init()),
                configuration: .init(address: .hostname(hostname, port: port))
            )

            logger.info("Server starting on \(hostname):\(port)")

            let bonjourAdvertiser = BonjourAdvertiser(port: port)

            let serviceGroup = ServiceGroup(
                configuration: ServiceGroupConfiguration(
                    services: [
                        .init(service: app),
                        .init(service: jobRunner),
                        .init(service: orphanCleanup),
                        .init(service: bonjourAdvertiser)
                    ],
                    gracefulShutdownSignals: [UnixSignal.sigterm, UnixSignal.sigint],
                    logger: logger
                )
            )

            return ServerContext(
                serviceGroup: serviceGroup,
                dependencies: DependencyValues._current
            )
        }
    }

    /// Default workspace path
    private static func defaultWorkspacePath() throws -> URL {
        let fileManager = FileManager.default
        let appName = "Monad"

        #if os(macOS)
            guard
                let appSupport = fileManager.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first
            else {
                // Fallback
                let home = fileManager.homeDirectoryForCurrentUser
                let workspacesDir = home.appendingPathComponent(
                    ".monad/workspaces", isDirectory: true)
                try? fileManager.createDirectory(
                    at: workspacesDir, withIntermediateDirectories: true)
                return workspacesDir
            }

            let appDir = appSupport.appendingPathComponent(appName, isDirectory: true)
            let workspacesDir = appDir.appendingPathComponent("Workspaces", isDirectory: true)
            try fileManager.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
            return workspacesDir

        #elseif os(Linux)
            let env = ProcessInfo.processInfo.environment
            let dataHome: URL
            if let xdgData = env["XDG_DATA_HOME"] {
                dataHome = URL(fileURLWithPath: xdgData)
            } else {
                dataHome = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local")
                    .appendingPathComponent("share")
            }

            let appDir = dataHome.appendingPathComponent(appName.lowercased(), isDirectory: true)
            let workspacesDir = appDir.appendingPathComponent("workspaces", isDirectory: true)
            try fileManager.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
            return workspacesDir

        #else
            // Fallback
            let home = fileManager.homeDirectoryForCurrentUser
            let workspacesDir = home.appendingPathComponent(".monad/workspaces", isDirectory: true)
            try fileManager.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
            return workspacesDir
        #endif
    }
}

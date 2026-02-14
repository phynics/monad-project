import ArgumentParser
import Foundation
import Hummingbird
import Logging
import MonadCore
import ServiceLifecycle
import UnixSignals
import HummingbirdWebSocket

@main
@available(macOS 14.0, *)
struct MonadServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monad-server",
        abstract: "Monad AI Assistant Server",
        discussion: """
            A REST API server for the Monad AI Assistant.

            EXAMPLES:
              monad-server                          Start on default port 8080
              monad-server --port 3000              Start on port 3000
              monad-server -h 0.0.0.0 -p 8080       Bind to all interfaces
              monad-server --verbose                Enable verbose logging

            API ENDPOINTS:
              GET  /health                          Health check
              GET  /api/sessions                    List sessions
              POST /api/sessions                    Create session
              POST /api/sessions/:id/chat/stream    Chat with streaming
              GET  /api/memories                    List memories
              GET  /api/notes                       List notes
              GET  /api/tools                       List tools
              GET  /api/config                      Get LLM configuration

            AUTHENTICATION:
              All /api/* endpoints require an API key via Authorization header.
            """,
        version: "1.0.0",
        helpNames: [.short, .long]
    )

    typealias AppRequestContext = BasicWebSocketRequestContext
    
    @Option(name: .shortAndLong, help: "Hostname to bind to")
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 8080

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    func run() async throws {
        // Initialize Persistence
        let persistenceService: PersistenceService
        let logger = Logger.server
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
        
        // Initialize Vector Store (Mocked for now)
        let vectorStore = MockVectorStore()
        try? await vectorStore.initialize() // Best effort init
        
        let llmService = ServerLLMService()
        await llmService.loadConfiguration()

        let workspaceRoot = try Self.defaultWorkspacePath()
        
        // Initialize WebSocket Manager
        let connectionManager = WebSocketConnectionManager()
        
        let sessionManager = SessionManager(
            persistenceService: persistenceService,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            llmService: llmService,
            workspaceRoot: workspaceRoot,
            connectionManager: connectionManager
        )

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
        
        // WebSocket Route
        let wsController = WebSocketAPIController<AppRequestContext>(connectionManager: connectionManager)
        wsController.addRoutes(to: router.group("/api"))

        // Protected routes
        let protected = router.group("/api")
            .add(middleware: AuthMiddleware())

        protected.get("/test") { _, _ -> String in
            return "Authenticated!"
        }

        let sessionController = SessionAPIController<AppRequestContext>(
            sessionManager: sessionManager)
        sessionController.addRoutes(to: protected.group("/sessions"))

        let chatController = ChatAPIController<AppRequestContext>(
            sessionManager: sessionManager, llmService: llmService, verbose: verbose)
        chatController.addRoutes(to: protected.group("/sessions"))

        let jobController = JobAPIController<AppRequestContext>(sessionManager: sessionManager)
        jobController.addRoutes(to: protected.group("/sessions"))

        let memoryController = MemoryAPIController<AppRequestContext>(sessionManager: sessionManager)
        memoryController.addRoutes(to: protected.group("/memories"))

        let pruneController = PruneAPIController<AppRequestContext>(
            persistenceService: persistenceService)
        pruneController.addRoutes(to: protected.group("/prune"))

        let toolController = ToolAPIController<AppRequestContext>(sessionManager: sessionManager)
        toolController.addRoutes(to: protected.group("/tools"))

        // Create database writer accessor (since it's an actor property, access it async or assume safe access pattern)
        let dbWriter = persistenceService.databaseWriter

        let workspacesGroup = protected.group("/workspaces")
        
        let workspaceAPIController = WorkspaceAPIController<AppRequestContext>(
            dbWriter: dbWriter, logger: logger)
        workspaceAPIController.addRoutes(to: workspacesGroup)

        let coreWorkspaceController = try await MonadCore.WorkspaceController(dbWriter: dbWriter)

        let filesController = FilesAPIController<AppRequestContext>(
            workspaceController: coreWorkspaceController)
        filesController.addRoutes(to: protected.group("/workspaces/:workspaceId/files"))

        let clientController = ClientAPIController<AppRequestContext>(
            dbWriter: dbWriter, logger: logger)
        clientController.addRoutes(to: protected.group("/clients"))

        let configController = ConfigurationAPIController<AppRequestContext>(llmService: llmService)
        configController.addRoutes(to: protected.group("/config"))
        
        // Add WS routes to main router as well if needed, or group
        // wsController.addRoutes(to: router.group("/ws"))

        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router, configuration: .init()),
            configuration: .init(address: .hostname(hostname, port: port))
        )

        logger.info("Server starting on \(hostname):\(port)")

        _ = BonjourAdvertiser(port: port)

        let jobRunner = JobRunnerService(sessionManager: sessionManager, llmService: llmService)
        let orphanCleanup = OrphanCleanupService(persistenceService: persistenceService, workspaceRoot: workspaceRoot, logger: logger)

        let serviceGroup = ServiceGroup(
            configuration: ServiceGroupConfiguration(
                services: [
                    .init(service: app),
                    .init(service: jobRunner),
                    // .init(service: advertiser),
                    .init(service: orphanCleanup)
                ],
                gracefulShutdownSignals: [UnixSignal.sigterm, UnixSignal.sigint],
                logger: logger
            )
        )

        try await serviceGroup.run()
    }

    /// Service to clean up orphaned workspaces
    struct OrphanCleanupService: Service {
        let persistenceService: PersistenceService
        let workspaceRoot: URL
        let logger: Logger

        func run() async throws {
            logger.info("OrphanCleanupService started")
            // Run initial cleanup
            await cleanup()
            
            // Then run periodically (every 24 hours)
            try await cancelWhenGracefulShutdown {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(86400)) // 24 hours
                        await cleanup()
                    } catch is CancellationError {
                        logger.info("OrphanCleanupService shutting down gracefully")
                        return
                    }
                }
            }
            logger.info("OrphanCleanupService stopped")
        }

        private func cleanup() async {
            logger.info("Starting orphaned workspace cleanup...")
            do {
                try await persistenceService.databaseWriter.write { db in
                    let workspaces = try WorkspaceReference.fetchAll(db)
                    let sessions = try ConversationSession.fetchAll(db)
                    
                    var referencedIds: Set<UUID> = []
                    
                    // Collect all referenced IDs
                    for session in sessions {
                        if let pid = session.primaryWorkspaceId {
                            referencedIds.insert(pid)
                        }
                        for aid in session.attachedWorkspaces {
                            referencedIds.insert(aid)
                        }
                    }
                    
                    var deletedCount = 0
                    for ws in workspaces {
                        if !referencedIds.contains(ws.id) {
                            // Check if it's safe to delete (is it in the Monad Workspaces dir?)
                            // We construct the path and check if the recorded rootPath matches
                            if let rootPath = ws.rootPath, 
                               rootPath.hasPrefix(workspaceRoot.path) || rootPath.contains("/.monad/workspaces/") || rootPath.contains("/Monad/Workspaces/") {
                                
                                // Delete DB Record
                                try ws.delete(db)
                                
                                // Delete Filesystem
                                if FileManager.default.fileExists(atPath: rootPath) {
                                    try? FileManager.default.removeItem(atPath: rootPath)
                                }
                                deletedCount += 1
                                logger.info("Deleted orphaned workspace: \(ws.id) at \(rootPath)")
                            } else {
                                logger.warning("Skipping cleanup of user-managed workspace: \(ws.id) at \(ws.rootPath ?? "nil")")
                            }
                        }
                    }
                    
                    if deletedCount > 0 {
                        logger.info("Cleanup complete. Removed \(deletedCount) orphaned workspaces.")
                    } else {
                        logger.info("Cleanup complete. No orphaned workspaces found.")
                    }
                }
            } catch {
                logger.error("Failed to run orphan cleanup: \(error)")
            }
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

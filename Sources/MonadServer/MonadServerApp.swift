import ArgumentParser
import Foundation
import Hummingbird
import Logging
import MonadCore
import ServiceLifecycle
import UnixSignals

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

        let router = Router()

        // Add Global Middleware
        router.add(middleware: LogMiddleware())
        router.add(middleware: ErrorMiddleware())

        let embeddingService = LocalEmbeddingService()
        let llmService = ServerLLMService()
        await llmService.loadConfiguration()

        let workspaceRoot = try Self.defaultWorkspacePath()

        let sessionManager = SessionManager(
            persistenceService: persistenceService,
            embeddingService: embeddingService,
            llmService: llmService,
            workspaceRoot: workspaceRoot
        )

        // Public routes
        router.get("/health") { _, _ -> String in
            return "OK"
        }

        let startTime = Date()
        let statusController = StatusController<BasicRequestContext>(
            persistenceService: persistenceService,
            llmService: llmService,
            startTime: startTime
        )
        statusController.addRoutes(to: router)

        router.get("/") { _, _ -> String in
            return "Monad Server is running."
        }

        // Protected routes
        let protected = router.group("/api")
            .add(middleware: AuthMiddleware())

        protected.get("/test") { _, _ -> String in
            return "Authenticated!"
        }

        let sessionController = SessionController<BasicRequestContext>(
            sessionManager: sessionManager)
        sessionController.addRoutes(to: protected.group("/sessions"))

        let chatController = ChatController<BasicRequestContext>(
            sessionManager: sessionManager, llmService: llmService, verbose: verbose)
        chatController.addRoutes(to: protected.group("/sessions"))

        let jobController = JobController<BasicRequestContext>(sessionManager: sessionManager)
        jobController.addRoutes(to: protected.group("/sessions"))

        let memoryController = MemoryController<BasicRequestContext>(sessionManager: sessionManager)
        memoryController.addRoutes(to: protected.group("/memories"))

        let pruneController = PruneController<BasicRequestContext>(
            persistenceService: persistenceService)
        pruneController.addRoutes(to: protected.group("/prune"))

        let toolController = ToolController<BasicRequestContext>(sessionManager: sessionManager)
        toolController.addRoutes(to: protected.group("/tools"))

        // Create database writer accessor (since it's an actor property, access it async or assume safe access pattern)
        let dbWriter = persistenceService.databaseWriter

        let workspaceController = WorkspaceController<BasicRequestContext>(
            dbWriter: dbWriter, logger: logger)
        workspaceController.addRoutes(to: protected.group("/workspaces"))

        let filesController = FilesController<BasicRequestContext>(
            workspaceController: workspaceController)
        filesController.addRoutes(to: protected.group("/workspaces/:id/files"))

        let clientController = ClientController<BasicRequestContext>(
            dbWriter: dbWriter, logger: logger)
        clientController.addRoutes(to: protected.group("/clients"))

        let configController = ConfigurationController<BasicRequestContext>(llmService: llmService)
        configController.addRoutes(to: protected.group("/config"))

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )

        logger.info("Server starting on \(hostname):\(port)")

        let advertiser = BonjourAdvertiser(port: port)

        let jobRunner = JobRunnerService(sessionManager: sessionManager, llmService: llmService)

        let serviceGroup = ServiceGroup(
            configuration: ServiceGroupConfiguration(
                services: [
                    .init(service: app),
                    .init(service: jobRunner),
                    .init(service: advertiser)
                ],
                gracefulShutdownSignals: [UnixSignal.sigterm, UnixSignal.sigint],
                logger: logger
            )
        )

        try await serviceGroup.run()
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

import ArgumentParser
import Foundation
import Hummingbird
import Logging
import MonadCore
import MonadServerCore

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
        let sessionManager = SessionManager(
            persistenceService: persistenceService, embeddingService: embeddingService,
            llmService: llmService)

        // Public routes
        router.get("/health") { _, _ -> String in
            return "OK"
        }

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

        let memoryController = MemoryController<BasicRequestContext>(sessionManager: sessionManager)
        memoryController.addRoutes(to: protected.group("/memories"))

        let noteController = NoteController<BasicRequestContext>(sessionManager: sessionManager)
        noteController.addRoutes(to: protected.group("/notes"))

        let toolController = ToolController<BasicRequestContext>(sessionManager: sessionManager)
        toolController.addRoutes(to: protected.group("/tools"))

        let configController = ConfigurationController<BasicRequestContext>(llmService: llmService)
        configController.addRoutes(to: protected.group("/config"))

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )

        logger.info("Server starting on \(hostname):\(port)")
        try await app.runService()
    }
}

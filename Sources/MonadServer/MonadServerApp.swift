import ArgumentParser
import Hummingbird
import Foundation
import OSLog
import MonadCore
import MonadServerCore

@main
@available(macOS 14.0, *)
struct MonadServer: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong)
    var port: Int = 8080

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
        let sessionManager = SessionManager(persistenceService: persistenceService, embeddingService: embeddingService, llmService: llmService)
        
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
        
        let sessionController = SessionController<BasicRequestContext>(sessionManager: sessionManager)
        sessionController.addRoutes(to: protected.group("/sessions"))
        
        let chatController = ChatController<BasicRequestContext>(sessionManager: sessionManager, llmService: llmService)
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



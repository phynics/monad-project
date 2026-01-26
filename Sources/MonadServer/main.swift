import ArgumentParser
import Hummingbird
import Foundation
import MonadCore
import MonadServerCore

struct MonadServer: AsyncParsableCommand {
    @Option(name: .shortAndLong)
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong)
    var port: Int = 8080

    func run() async throws {
        // Initialize Persistence
        let persistenceService: PersistenceService
        do {
            persistenceService = try PersistenceService.create()
            print("Persistence initialized.")
        } catch {
            print("Failed to initialize persistence: \(error)")
            throw error
        }

        let router = Router()
        let embeddingService = LocalEmbeddingService()
        let sessionManager = SessionManager(persistenceService: persistenceService, embeddingService: embeddingService)
        let llmService = ServerLLMService()
        await llmService.loadConfiguration()
        
        // Public routes
        router.get("/health") { _, _ -> String in
            return "OK"
        }
        
        // Protected routes
        let protected = router.group("/api")
            .add(middleware: AuthMiddleware())
            
        protected.get("/test") { _, _ -> String in
            return "Authenticated!"
        }
        
        let sessionController = SessionController<BasicRequestContext>(sessionManager: sessionManager)
        sessionController.addRoutes(to: protected.group("/sessions"))

        let app = Application(
            router: router,
            configuration: .init(address: .hostname(hostname, port: port))
        )

        print("Server starting on \(hostname):\(port)")
        try await app.runService()
    }
}

await MonadServer.main()

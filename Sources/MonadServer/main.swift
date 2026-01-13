import Foundation
import GRPC
import NIOPosix
import MonadCore
import MonadServerCore
import NIOCore

// 1. Initialize Observability
let serverMetrics = ServerMetrics()
serverMetrics.bootstrap()

// 2. Initialize Core Services
// TODO: Load configuration from env or file
// For server, we might want to specify a fixed path or use a default one
let persistence = try await PersistenceService.create()
let llm = LLMService()

// Load LLM config
await llm.loadConfiguration()

// 3. Setup Handlers
let chatHandler = ChatHandler(llm: llm, persistence: persistence)
let sessionHandler = SessionHandler(persistence: persistence)
let memoryHandler = MemoryHandler(persistence: persistence)
let noteHandler = NoteHandler(persistence: persistence)
let jobHandler = JobHandler(persistence: persistence)

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

// 4. Start Metrics Server (Background)
Task {
    do {
        try await serverMetrics.startMetricsServer(port: 8080)
    } catch {
        print("Failed to start metrics server: \(error)")
    }
}

// 5. Start gRPC Server
let server = try await Server.insecure(group: group)
    .withServiceProviders([
        chatHandler,
        sessionHandler,
        memoryHandler,
        noteHandler,
        jobHandler
    ])
    .bind(host: "0.0.0.0", port: 50051)
    .get()

print("Monad Server started on \(server.channel.localAddress!)")

// Wait for the server to close
try await server.onClose.get()

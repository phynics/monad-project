import Foundation
import GRPC
import NIOPosix
import MonadCore
import NIOCore

// Initialize services
// TODO: Load configuration from env or file
// For server, we might want to specify a fixed path or use a default one
let persistence = try await PersistenceService.create()
let llm = LLMService()

// Load LLM config
await llm.loadConfiguration()

// Handlers (Async versions from MonadCore)
let chatHandler = ChatHandler(llm: llm, persistence: persistence)
let sessionHandler = SessionHandler(persistence: persistence)
let memoryHandler = MemoryHandler(persistence: persistence)
let noteHandler = NoteHandler(persistence: persistence)
let jobHandler = JobHandler(persistence: persistence)

let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

// Start server
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

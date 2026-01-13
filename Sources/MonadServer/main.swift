import Foundation
import MonadCore
import MonadServerCore
import Logging

// 1. Initialize Core Infrastructure
let metrics = ServerMetrics()
let errorHandler = ServerErrorHandler()

// 2. Initialize Core Domain Services
let persistence = try await PersistenceService.create()
let llm = LLMService()

// 3. Initialize gRPC Handlers (Decoupled via Protocols)
let chatHandler = ChatHandler(llm: llm, persistence: persistence)
let sessionHandler = SessionHandler(persistence: persistence)
let memoryHandler = MemoryHandler(persistence: persistence)
let noteHandler = NoteHandler(persistence: persistence)
let jobHandler = JobHandler(persistence: persistence)

// 4. Initialize Service Providers
let metricsProvider = MetricsServerProvider(metrics: metrics)
let grpcProvider = GRPCServerProvider(handlers: [
    chatHandler,
    sessionHandler,
    memoryHandler,
    noteHandler,
    jobHandler
])

// 5. Initialize Central Orchestrator
let orchestrator = ServiceProviderOrchestrator(
    persistence: persistence,
    llm: llm,
    errorHandler: errorHandler,
    metrics: metrics,
    additionalProviders: [metricsProvider, grpcProvider]
)

// 6. Startup Sequence
do {
    try await orchestrator.startup()
    
    print("Monad Server is running.")
    
    // Wait for the gRPC server to close
    try await grpcProvider.onClose?.get()
} catch {
    print("CRITICAL: Failed to start Monad Server: \(error)")
    exit(1)
}

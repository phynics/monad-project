import Foundation
import MonadCore
import Logging
import ServiceLifecycle

public final class JobRunnerService: Service, Sendable {
    private let sessionManager: SessionManager
    private let llmService: any LLMServiceProtocol
    private let logger = Logger(label: "com.monad.job-runner")
    
    public init(sessionManager: SessionManager, llmService: any LLMServiceProtocol) {
        self.sessionManager = sessionManager
        self.llmService = llmService
    }
    
    public func run() async throws {
        logger.info("Job Runner Service started")
        
        // Use cancelWhenGracefulShutdown to properly respond to shutdown signals
        try await cancelWhenGracefulShutdown {
            // Main Loop
            while !Task.isCancelled {
                do {
                    try await self.processNextJob()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    self.logger.error("Error processing job: \(error)")
                }
                
                // Sleep for a bit to avoid tight loop if no jobs
                // In a real system, we might use a signal/notification or exponential backoff
                try await Task.sleep(nanoseconds: 2 * 1_000_000_000) // 2 seconds
            }
        }
        
        logger.info("Job Runner Service stopped")
    }
    
    private func processNextJob() async throws {
        // We need to iterate over all sessions to find pending jobs.
        // This is inefficient if we have many sessions. 
        // Ideally we'd have a global job queue query.
        // `PersistenceService` has `fetchAllJobs`, but `JobQueueContext` is per session.
        // The implementation plan says "Use fetchAllJobs" or "Global Queue".
        
        let persistence = await sessionManager.getPersistenceService()
        
        // 1. Fetch ALL pending jobs globally (sorted by priority)
        // We need a method on PersistenceService for this efficiently.
        // For now, let's fetch all jobs and filter in memory (not ideal but works for V1)
        let allJobs = try await persistence.fetchAllJobs()
        let pendingJobs = allJobs.filter { $0.status == .pending }
            .sorted { $0.priority > $1.priority }
        
        guard let nextJob = pendingJobs.first else {
            return
        }
        
        // 2. Identify Session
        guard let session = await sessionManager.getSession(id: nextJob.sessionId) else {
            logger.warning("Found pending job \(nextJob.id) but session \(nextJob.sessionId) not found. Marking as failed.")
            var failedJob = nextJob
            failedJob.status = .cancelled
            failedJob.updatedAt = Date()
            try await persistence.saveJob(failedJob)
            return
        }
        
        // 3. Ensure Session is Hydrated
        do {
            try await sessionManager.hydrateSession(id: session.id)
        } catch {
             logger.error("Failed to hydrate session \(session.id): \(error)")
             return
        }

        // 4. Get ToolExecutor
        guard let toolExecutor = await sessionManager.getToolExecutor(for: session.id) else {
            logger.warning("ToolExecutor for session \(session.id) not found even after hydration.")
            return
        }
        
        
        // 5. Initialize Agent with ContextManager (RAG)
        let contextManager = await sessionManager.getContextManager(for: session.id)
        let agent = AutonomousAgent(
            llmService: llmService,
            persistenceService: persistence,
            contextManager: contextManager
        )
        
        // 6. Execute
        await agent.execute(job: nextJob, session: session, toolExecutor: toolExecutor)
    }
}

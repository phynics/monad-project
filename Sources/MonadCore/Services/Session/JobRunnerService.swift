import Foundation
import Logging

/// Service that monitors and executes background jobs
public final class JobRunnerService: Sendable {
    private let sessionManager: SessionManager
    private let llmService: any LLMServiceProtocol
    private let agentRegistry: AgentRegistry
    private let logger = Logger(label: "com.monad.job-runner")
    
    public init(sessionManager: SessionManager, llmService: any LLMServiceProtocol, agentRegistry: AgentRegistry) {
        self.sessionManager = sessionManager
        self.llmService = llmService
        self.agentRegistry = agentRegistry
    }
    
    /// Run the job execution loop
    public func run() async throws {
        logger.info("Job Runner Service started (Event Driven)")
        
        let persistence = await self.sessionManager.getPersistenceService()
        
        // Initial scan
        try? await self.processPendingJobs(persistence)
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            // 1. Event Stream Listener
            group.addTask {
                for await event in await persistence.monitorJobs() {
                    if Task.isCancelled { break }
                    switch event {
                    case .jobUpdated(let job):
                         if job.status == .pending {
                             // Immediate processing if ready and no schedule delay
                             if let nextRun = job.nextRunAt, nextRun > Date() {
                                 continue
                             }
                             try? await self.processJob(job, persistence: persistence)
                         }
                    case .jobDeleted:
                         break
                    }
                }
            }
            
            // 2. Periodic Scanner (for scheduled jobs and fail-safety)
            group.addTask {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10 * 1_000_000_000) // Check every 10s
                    try? await self.processPendingJobs(persistence)
                }
            }
            
            // Wait for cancellation or tasks to finish
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            group.cancelAll()
        }
        
        logger.info("Job Runner Service stopped")
    }
    
    private func processPendingJobs(_ persistence: any PersistenceServiceProtocol) async throws {
        // Fetch pending jobs using new efficient query
        let jobs = try await persistence.fetchPendingJobs(limit: 5)
        for job in jobs {
            if Task.isCancelled { break }
            try await processJob(job, persistence: persistence)
        }
    }
    
    private func processJob(_ job: Job, persistence: any PersistenceServiceProtocol) async throws {
        // 1. Identify Session
        guard let session = await sessionManager.getSession(id: job.sessionId) else {
            logger.warning("Found pending job \(job.id) but session \(job.sessionId) not found. Marking as failed.")
            var failedJob = job
            failedJob.status = .cancelled
            failedJob.updatedAt = Date()
            failedJob.logs.append("Session not found")
            try await persistence.saveJob(failedJob)
            return
        }
        
        // 2. Ensure Session is Hydrated
        do {
            try await sessionManager.hydrateSession(id: session.id, parentId: job.id)
        } catch {
             logger.error("Failed to hydrate session \(session.id): \(error)")
             return
        }

        // 3. Get ToolExecutor
        guard let toolExecutor = await sessionManager.getToolExecutor(for: session.id) else {
            logger.warning("ToolExecutor for session \(session.id) not found even after hydration.")
            return
        }
        
        // 4. Initialize Agent with ContextManager (RAG)
        let contextManager = await sessionManager.getContextManager(for: session.id)

        // 5. Resolve Agent
        let agentId = job.agentId
        guard let agent = await agentRegistry.getAgent(id: agentId) else {
            logger.error("Agent with ID '\(agentId)' not found for job \(job.id)")
            // Optionally mark job as failed here
            return
        }

        // 6. Execute
        await agent.execute(
            job: job,
            session: session,
            toolExecutor: toolExecutor,
            contextManager: contextManager
        )
    }
}

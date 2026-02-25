import MonadCore
import MonadShared
import Foundation
import Logging
import ServiceLifecycle
import Dependencies

/// Service that monitors and executes background jobs
public final class JobRunnerService: Service, @unchecked Sendable {
    private let sessionManager: SessionManager
    private let agentRegistry: AgentRegistry
    private let agentExecutor: AgentExecutor

    private let logger = Logger(label: "com.monad.job-runner")

    public init(
        sessionManager: SessionManager,
        agentRegistry: AgentRegistry,
        agentExecutor: AgentExecutor
    ) {
        self.sessionManager = sessionManager
        self.agentRegistry = agentRegistry
        self.agentExecutor = agentExecutor
    }

    /// Run the job execution loop
    public func run() async throws {
        logger.info("Job Runner Service started (Event Driven)")

        let persistence = await self.sessionManager.getPersistenceService()

        // Initial scan
        do {
            try await self.processPendingJobs(persistence)
        } catch {
            logger.error("Initial job scan failed: \(error)")
        }

        try await cancelWhenGracefulShutdown {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // 1. Event Stream Listener
                group.addTask {
                    for await event in await persistence.monitorJobs() {
                        if Task.isCancelled { break }
                        switch event {
                        case .jobAdded(let job), .jobUpdated(let job):
                             if job.status == .pending {
                                 // Immediate processing if ready and no schedule delay
                                 if let nextRun = job.nextRunAt, nextRun > Date() {
                                     continue
                                 }
                                 do {
                                     try await self.processJob(job, persistence: persistence)
                                 } catch {
                                     self.logger.error("Failed to process event-driven job \(job.id): \(error)")
                                 }
                             }
                        case .jobDeleted:
                             break
                        }
                    }
                }

                // 2. Periodic Scanner (for scheduled jobs and fail-safety)
                group.addTask {
                    while !Task.isCancelled {
                        do {
                            try await Task.sleep(nanoseconds: 10 * 1_000_000_000) // Check every 10s
                            try await self.processPendingJobs(persistence)
                        } catch is CancellationError {
                            break
                        } catch {
                            self.logger.error("Periodic job scan failed: \(error)")
                        }
                    }
                }

                // Wait for all tasks to complete/cancel
                try await group.waitForAll()
            }
        }

        logger.info("Job Runner Service stopped")
    }

    private func processPendingJobs(_ persistence: any JobStoreProtocol) async throws {
        // Fetch pending jobs using new efficient query
        let jobs = try await persistence.fetchPendingJobs(limit: 5)
        for job in jobs {
            if Task.isCancelled { break }
            try await processJob(job, persistence: persistence)
        }
    }

    private func processJob(_ job: Job, persistence: any JobStoreProtocol) async throws {
        // 1. Identify Session
        guard let session = await sessionManager.getSession(id: job.sessionId) else {
            let reason = "Session \(job.sessionId) not found"
            logger.warning("Found pending job \(job.id) but \(reason). Marking as failed.")
            await agentExecutor.failJob(job, reason: reason)
            return
        }

        // 2. Ensure Session is Hydrated
        do {
            try await sessionManager.hydrateSession(id: session.id, parentId: job.id)
        } catch {
            await agentExecutor.failJob(job, reason: "Failed to hydrate session: \(error.localizedDescription)")
            return
        }

        // 3. Get ToolExecutor
        guard let toolExecutor = await sessionManager.getToolExecutor(for: session.id) else {
            await agentExecutor.failJob(job, reason: "ToolExecutor not found after hydration")
            return
        }

        // 4. Initialize Agent with ContextManager (RAG)
        let contextManager = await sessionManager.getContextManager(for: session.id)

        // 5. Resolve Agent
        let agentId = job.agentId
        guard let agent = await agentRegistry.getAgent(id: agentId) else {
            await agentExecutor.failJob(job, reason: "Agent '\(agentId)' not found")
            return
        }

        // 6. Execute
        await agentExecutor.execute(
            job: job,
            agent: agent,
            session: session,
            toolExecutor: toolExecutor,
            contextManager: contextManager
        )
    }
}

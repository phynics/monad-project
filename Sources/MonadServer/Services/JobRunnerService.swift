import Dependencies
import Foundation
import Logging
import MonadCore
import ServiceLifecycle

/// Service that monitors and executes background jobs
public final class JobRunnerService: Service, @unchecked Sendable {
    private let sessionManager: SessionManager
    private let msAgentRegistry: MSAgentRegistry
    private let msAgentExecutor: MSAgentExecutor

    private let logger = Logger(label: "com.monad.job-runner")

    public init(
        sessionManager: SessionManager,
        msAgentRegistry: MSAgentRegistry,
        msAgentExecutor: MSAgentExecutor
    ) {
        self.sessionManager = sessionManager
        self.msAgentRegistry = msAgentRegistry
        self.msAgentExecutor = msAgentExecutor
    }

    /// Run the job execution loop
    public func run() async throws {
        logger.info("Job Runner Service started (Event Driven)")

        let persistence = await sessionManager.getPersistenceService()

        // Initial scan
        do {
            try await processPendingJobs(persistence)
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
                        case let .jobAdded(job), let .jobUpdated(job):
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

    private func processJob(_ job: Job, persistence _: any JobStoreProtocol) async throws {
        let sid = ANSIColors.colorize(job.sessionId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
        let jid = ANSIColors.colorize(job.id.uuidString.prefix(8).lowercased(), color: ANSIColors.dim)
        let jobTitle = ANSIColors.colorize(job.title, color: ANSIColors.brightCyan)

        logger.info("Processing job \(jid) [\(jobTitle)] in session \(sid)")

        // 1. Identify Session
        guard let session = await sessionManager.getSession(id: job.sessionId) else {
            let reason = "Session \(job.sessionId) not found"
            logger.warning("Found pending job \(jid) but \(reason). Marking as failed.")
            await msAgentExecutor.failJob(job, reason: reason)
            return
        }

        // 2. Ensure Session is Hydrated
        do {
            try await sessionManager.hydrateSession(id: session.id, parentId: job.id)
        } catch {
            await msAgentExecutor.failJob(job, reason: "Failed to hydrate session: \(error.localizedDescription)")
            return
        }

        // 3. Get ToolExecutor
        guard let toolExecutor = await sessionManager.getToolExecutor(for: session.id) else {
            await msAgentExecutor.failJob(job, reason: "ToolExecutor not found after hydration")
            return
        }

        // 4. Initialize MSAgent with ContextManager (RAG)
        let contextManager = await sessionManager.getContextManager(for: session.id)

        // 5. Resolve MSAgent
        let agentId = job.agentId
        guard let agent = await msAgentRegistry.getMSAgent(id: agentId) else {
            logger.error("MSAgent '\(agentId)' not found for job \(jid)")
            await msAgentExecutor.failJob(job, reason: "MSAgent '\(agentId)' not found")
            return
        }

        logger.info("Executing job \(jid) with agent \(ANSIColors.colorize(agentId, color: ANSIColors.brightMagenta))")

        // 6. Execute
        await msAgentExecutor.execute(
            job: job,
            agent: agent,
            session: session,
            toolExecutor: toolExecutor,
            contextManager: contextManager
        )
    }
}

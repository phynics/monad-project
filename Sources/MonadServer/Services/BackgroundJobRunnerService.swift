import MonadShared
import Dependencies
import Foundation
import Logging
import MonadCore
import ServiceLifecycle

/// Service that monitors and executes background jobs
public final class BackgroundJobRunnerService: Service, @unchecked Sendable {
    private let timelineManager: TimelineManager
    private let msAgentRegistry: MSAgentRegistry
    private let msAgentExecutor: MSAgentExecutor

    private let logger = Logger(label: "com.monad.job-runner")

    public init(
        timelineManager: TimelineManager,
        msAgentRegistry: MSAgentRegistry,
        msAgentExecutor: MSAgentExecutor
    ) {
        self.timelineManager = timelineManager
        self.msAgentRegistry = msAgentRegistry
        self.msAgentExecutor = msAgentExecutor
    }

    /// Run the job execution loop
    public func run() async throws {
        logger.info("BackgroundJob Runner Service started (Event Driven)")

        let persistence = await timelineManager.getPersistenceService()

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

        logger.info("BackgroundJob Runner Service stopped")
    }

    private func processPendingJobs(_ persistence: any BackgroundJobStoreProtocol) async throws {
        // Fetch pending jobs using new efficient query
        let jobs = try await persistence.fetchPendingJobs(limit: 5)
        for job in jobs {
            if Task.isCancelled { break }
            try await processJob(job, persistence: persistence)
        }
    }

    private func processJob(_ job: BackgroundJob, persistence _: any BackgroundJobStoreProtocol) async throws {
        let sid = ANSIColors.colorize(job.timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
        let jid = ANSIColors.colorize(job.id.uuidString.prefix(8).lowercased(), color: ANSIColors.dim)
        let jobTitle = ANSIColors.colorize(job.title, color: ANSIColors.brightCyan)

        logger.info("Processing job \(jid) [\(jobTitle)] in timeline \(sid)")

        // 1. Identify Timeline
        guard let timeline = await timelineManager.getTimeline(id: job.timelineId) else {
            let reason = "Timeline \(job.timelineId) not found"
            logger.warning("Found pending job \(jid) but \(reason). Marking as failed.")
            await msAgentExecutor.failJob(job, reason: reason)
            return
        }

        // 2. Ensure Timeline is Hydrated
        do {
            try await timelineManager.hydrateTimeline(id: timeline.id, parentId: job.id)
        } catch {
            await msAgentExecutor.failJob(job, reason: "Failed to hydrate timeline: \(error.localizedDescription)")
            return
        }

        // 3. Get ToolExecutor
        guard let toolExecutor = await timelineManager.getToolExecutor(for: timeline.id) else {
            await msAgentExecutor.failJob(job, reason: "ToolExecutor not found after hydration")
            return
        }

        // 4. Initialize MSAgent with ContextManager (RAG)
        let contextManager = await timelineManager.getContextManager(for: timeline.id)

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
            timeline: timeline,
            toolExecutor: toolExecutor,
            contextManager: contextManager
        )
    }
}

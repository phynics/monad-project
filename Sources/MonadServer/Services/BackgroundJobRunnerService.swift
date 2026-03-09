import Dependencies
import Foundation
import Logging
import MonadCore
import MonadShared
import ServiceLifecycle

/// Service that monitors and executes background jobs
public final class BackgroundJobRunnerService: Service, @unchecked Sendable {
    private let timelineManager: TimelineManager
    private let chatEngine: ChatEngine
    @Dependency(\.backgroundJobStore) private var backgroundJobStore
    @Dependency(\.agentTemplateStore) private var agentTemplateStore
    @Dependency(\.messageStore) private var messageStore

    private let logger = Logger(label: "com.monad.job-runner")

    public init(timelineManager: TimelineManager, chatEngine: ChatEngine) {
        self.timelineManager = timelineManager
        self.chatEngine = chatEngine
    }

    /// Run the job execution loop
    public func run() async throws {
        logger.info("BackgroundJob Runner Service started (Event Driven)")

        // Initial scan
        do {
            try await processPendingJobs(backgroundJobStore)
        } catch {
            logger.error("Initial job scan failed: \(error)")
        }

        try await cancelWhenGracefulShutdown {
            try await withThrowingTaskGroup(of: Void.self) { group in
                // 1. Event Stream Listener
                group.addTask {
                    for await event in await self.backgroundJobStore.monitorJobs() {
                        if Task.isCancelled { break }
                        switch event {
                        case let .jobAdded(job), let .jobUpdated(job):
                            if job.status == .pending {
                                if let nextRun = job.nextRunAt, nextRun > Date() {
                                    continue
                                }
                                do {
                                    try await self.processJob(job, persistence: self.backgroundJobStore)
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
                            try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                            try await self.processPendingJobs(self.backgroundJobStore)
                        } catch is CancellationError {
                            break
                        } catch {
                            self.logger.error("Periodic job scan failed: \(error)")
                        }
                    }
                }

                try await group.waitForAll()
            }
        }

        logger.info("BackgroundJob Runner Service stopped")
    }

    private func processPendingJobs(_ persistence: any BackgroundJobStoreProtocol) async throws {
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

        guard let timeline = await timelineManager.getTimeline(id: job.timelineId) else {
            await failJob(job, reason: "Timeline \(job.timelineId) not found")
            return
        }

        do {
            try await timelineManager.hydrateTimeline(id: timeline.id, parentId: job.id)
        } catch {
            await failJob(job, reason: "Failed to hydrate timeline: \(error.localizedDescription)")
            return
        }

        guard let toolExecutor = await timelineManager.getToolExecutor(for: timeline.id) else {
            await failJob(job, reason: "ToolExecutor not found after hydration")
            return
        }

        let contextManager = await timelineManager.getContextManager(for: timeline.id)

        let agentId = job.agentId
        guard let agent = try? await agentTemplateStore.fetchAgentTemplate(key: agentId) else {
            logger.error("AgentTemplate '\(agentId)' not found for job \(jid)")
            await failJob(job, reason: "AgentTemplate '\(agentId)' not found")
            return
        }

        logger.info("Executing job \(jid) with agent \(ANSIColors.colorize(agentId, color: ANSIColors.brightMagenta))")
        await executeJob(job, agent: agent, timeline: timeline, toolExecutor: toolExecutor, contextManager: contextManager)
    }

    // MARK: - Job Execution

    private func executeJob(
        _ job: BackgroundJob,
        agent: AgentTemplate,
        timeline: Timeline,
        toolExecutor: ToolExecutor,
        contextManager: ContextManager?
    ) async {
        logger.info("Starting execution of job: \(job.id) with agent \(agent.id)")

        var currentJob = job
        if currentJob.status != .inProgress {
            currentJob.status = .inProgress
            currentJob.updatedAt = Date()
            currentJob.logs.append("AgentTemplate \(agent.id) started execution at \(Date())")
            try? await backgroundJobStore.saveJob(currentJob)
        }

        if currentJob.logs.count <= 2 {
            let jobPrompt = """
            [TASK EXECUTION]
            Task: \(job.title)
            Description: \(job.description ?? "N/A")

            Please execute this task.
            When finished, state 'BackgroundJob Complete'.
            """
            let triggerMessage = ConversationMessage(
                timelineId: timeline.id,
                role: .user,
                content: jobPrompt,
                timestamp: Date()
            )
            try? await messageStore.saveMessage(triggerMessage)
        }

        do {
            let availableTools = await toolExecutor.getAvailableTools()
            let stream = try await chatEngine.chatStream(
                timelineId: timeline.id,
                message: "Continue execution",
                tools: availableTools,
                contextManager: contextManager,
                systemInstructions: agent.composedInstructions,
                maxTurns: 10
            )

            var fullContent = ""
            for try await event in stream {
                if let text = event.textContent {
                    fullContent += text
                } else if let completed = event.completedMessage {
                    fullContent = completed.message.content
                }
            }

            currentJob.status = .completed
            currentJob.updatedAt = Date()
            currentJob.logs.append("Task completed: \(fullContent.prefix(100))...")
            try? await backgroundJobStore.saveJob(currentJob)
        } catch {
            await failJob(currentJob, reason: error.localizedDescription)
        }
    }

    private func failJob(_ job: BackgroundJob, reason: String) async {
        logger.error("BackgroundJob \(job.id) failed: \(reason)")

        var currentJob = job
        currentJob.updatedAt = Date()
        currentJob.logs.append("Error: \(reason)")

        let maxRetries = 3
        if currentJob.retryCount < maxRetries {
            currentJob.retryCount += 1
            let backoff = TimeInterval(5 * Int(pow(2.0, Double(currentJob.retryCount))))
            currentJob.nextRunAt = Date().addingTimeInterval(backoff)
            currentJob.lastRetryAt = Date()
            currentJob.status = .pending
            currentJob.logs.append("Retrying in \(Int(backoff))s (Attempt \(currentJob.retryCount)/\(maxRetries))")
        } else {
            currentJob.status = .failed
            currentJob.logs.append("Max retries reached. BackgroundJob failed permanently.")
            let msg = ConversationMessage(
                timelineId: job.timelineId,
                role: .system,
                content: "BackgroundJob [\(job.id.uuidString.prefix(8))] Failed: \(reason)",
                timestamp: Date()
            )
            try? await messageStore.saveMessage(msg)
        }

        try? await backgroundJobStore.saveJob(currentJob)
    }
}

import MonadShared
import Foundation
import Logging
import Dependencies

/// Service responsible for executing autonomous agentTemplates and managing their reasoning loops.
public struct AgentTemplateExecutor: Sendable {
    private let backgroundJobStore: any BackgroundJobStoreProtocol
    private let messageStore: any MessageStoreProtocol
    private let chatEngine: ChatEngine

    private let logger = Logger.module(named: "agent-executor")

    public init(backgroundJobStore: any BackgroundJobStoreProtocol, messageStore: any MessageStoreProtocol, chatEngine: ChatEngine) {
        self.backgroundJobStore = backgroundJobStore
        self.messageStore = messageStore
        self.chatEngine = chatEngine
    }

    /// Execute an agent for a specific job
    public func execute(
        job: BackgroundJob,
        agent: AgentTemplate,
        timeline: Timeline,
        toolExecutor: ToolExecutor,
        contextManager: ContextManager?
    ) async {
        logger.info("Starting execution of job: \(job.id) with agent \(agent.id)")

        // 1. Update status to in_progress
        var currentJob = job
        if currentJob.status != .inProgress {
            currentJob.status = .inProgress
            currentJob.updatedAt = Date()
            currentJob.logs.append("AgentTemplate \(agent.id) started execution at \(Date())")
            try? await backgroundJobStore.saveJob(currentJob)
        }

        // 2. Construct Initial Trigger Message if this is the start of the job
        if currentJob.logs.count <= 2 { // Rough check for fresh job
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

        // 3. Run Chat Engine — consume stream internally for state tracking
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

            // Stream finished naturally — mark job complete
            currentJob.status = .completed
            currentJob.updatedAt = Date()
            currentJob.logs.append("Task completed: \(fullContent.prefix(100))...")
            try? await backgroundJobStore.saveJob(currentJob)
        } catch {
            await failJob(currentJob, reason: error.localizedDescription)
        }
    }

    /// Shared failure logic with retry mechanism
    public func failJob(_ job: BackgroundJob, reason: String) async {
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

import MonadShared
import Foundation
import Logging
import Dependencies

/// Service responsible for executing autonomous agents and managing their reasoning loops.
public struct AgentExecutor: Sendable {
    @Dependency(\.persistenceService) private var persistenceService
    @Dependency(\.reasoningEngine) private var reasoningEngine
    
    private let logger = Logger(label: "com.monad.agent-executor")
    
    public init() {}
    
    /// Execute an agent for a specific job
    public func execute(
        job: Job,
        agent: Agent,
        session: ConversationSession,
        toolExecutor: ToolExecutor,
        contextManager: ContextManager?
    ) async {
        logger.info("Starting execution of job: \(job.id) with agent \(agent.id)")

        // 1. Update status to in_progress
        var currentJob = job
        if currentJob.status != .inProgress {
            currentJob.status = .inProgress
            currentJob.updatedAt = Date()
            currentJob.logs.append("Agent \(agent.id) started execution at \(Date())")
            try? await persistenceService.saveJob(currentJob)
        }

        // 2. Ensure Session is Hydrated (Handled by JobRunner)
        
        // 3. Construct Initial Trigger Message if this is the start of the job
        if currentJob.logs.count <= 2 { // Rough check for fresh job
            let jobPrompt = """
                [TASK EXECUTION]
                Task: \(job.title)
                Description: \(job.description ?? "N/A")
                
                Please execute this task.
                When finished, state 'Job Complete'.
                """
            
            let triggerMessage = ConversationMessage(
                sessionId: session.id,
                role: .user,
                content: jobPrompt,
                timestamp: Date()
            )
            try? await persistenceService.saveMessage(triggerMessage)
        }
        
        // 4. Run Reasoning Loop
        do {
            let result = try await reasoningEngine.runLoop(
                job: job,
                session: session,
                toolExecutor: toolExecutor,
                contextManager: contextManager,
                systemInstructions: agent.composedInstructions
            )
            
            switch result {
            case .complete(let content):
                currentJob.status = .completed
                currentJob.updatedAt = Date()
                currentJob.logs.append("Task completed: \(content.prefix(100))...")
            case .needInformation(let content):
                currentJob.status = .completed // Synthetic completion
                currentJob.logs.append("Task paused: Need information: \(content.prefix(100))")
            case .error(let reason):
                await failJob(currentJob, reason: reason)
                return
            case .continueLoop:
                break
            }
            try? await persistenceService.saveJob(currentJob)
        } catch {
            await failJob(currentJob, reason: error.localizedDescription)
        }
    }

    /// Shared failure logic with retry mechanism
    public func failJob(_ job: Job, reason: String) async {
        logger.error("Job \(job.id) failed: \(reason)")
        
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
            currentJob.logs.append("Max retries reached. Job failed permanently.")
            
            let msg = ConversationMessage(
                sessionId: job.sessionId,
                role: .system,
                content: "Job [\(job.id.uuidString.prefix(8))] Failed: \(reason)",
                timestamp: Date()
            )
            try? await persistenceService.saveMessage(msg)
        }
        
        try? await persistenceService.saveJob(currentJob)
    }
}

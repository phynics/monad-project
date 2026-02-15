import Foundation
import Logging
import Dependencies

/// A base class for agents that provides common functionality and reduces boilerplate
open class BaseAgent: AgentProtocol, @unchecked Sendable {
    public let manifest: AgentManifest
    
    @Dependency(\.llmService) private var defaultLLMService
    @Dependency(\.persistenceService) private var defaultPersistenceService
    @Dependency(\.reasoningEngine) private var defaultReasoningEngine
    
    private let explicitLLMService: (any LLMServiceProtocol)?
    private let explicitPersistenceService: (any PersistenceServiceProtocol)?
    private let explicitReasoningEngine: ReasoningEngine?

    public var llmService: any LLMServiceProtocol { explicitLLMService ?? defaultLLMService }
    public var persistenceService: any PersistenceServiceProtocol { explicitPersistenceService ?? defaultPersistenceService }
    public var reasoningEngine: ReasoningEngine { explicitReasoningEngine ?? defaultReasoningEngine }
    
    public let logger: Logger

    public init(
        manifest: AgentManifest,
        llmService: (any LLMServiceProtocol)? = nil,
        persistenceService: (any PersistenceServiceProtocol)? = nil,
        reasoningEngine: ReasoningEngine? = nil
    ) {
        self.manifest = manifest
        self.explicitLLMService = llmService
        self.explicitPersistenceService = persistenceService
        self.explicitReasoningEngine = reasoningEngine
        
        self.logger = Logger(label: "com.monad.agent.\(manifest.id)")
    }

    /// The system instructions for this specific agent. Override in subclasses.
    open var systemInstructions: String {
        "You are an autonomous agent named \(manifest.name). \(manifest.description)"
    }

    /// Primary execution entry point
    open func execute(
        job: Job,
        session: ConversationSession,
        toolExecutor: ToolExecutor,
        contextManager: ContextManager?
    ) async {
        logger.info("Starting execution of job: \(job.id)")

        // 1. Update status to in_progress
        var currentJob = job
        if currentJob.status != .inProgress {
            currentJob.status = .inProgress
            currentJob.updatedAt = Date()
            currentJob.logs.append("Agent \(manifest.id) started execution at \(Date())")
            try? await persistenceService.saveJob(currentJob)
        }

        // 2. Initial Setup
        guard (try? await persistenceService.fetchMessages(for: session.id)) != nil else {
            await failJob(currentJob, reason: "Failed to load session history")
            return
        }

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
                systemInstructions: self.systemInstructions
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

    /// Shared failure logic
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

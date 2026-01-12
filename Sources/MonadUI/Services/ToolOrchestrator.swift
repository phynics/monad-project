import Foundation
import MonadCore
import OSLog

/// Orchestrates tool execution and integrates results back into the conversation state.
@MainActor
public final class ToolOrchestrator {
    public weak var delegate: (any SQLConfirmationDelegate)?
    
    private let toolExecutorProvider: @MainActor () -> ToolExecutor
    private var toolExecutor: ToolExecutor { toolExecutorProvider() }
    
    private let persistenceManager: PersistenceManager
    private let jobQueueContext: JobQueueContext
    private let logger = Logger(subsystem: "com.monad.ui", category: "ToolOrchestrator")
    
    public init(
        toolExecutor: @MainActor @escaping @autoclosure () -> ToolExecutor,
        persistenceManager: PersistenceManager,
        jobQueueContext: JobQueueContext
    ) {
        self.toolExecutorProvider = toolExecutor
        self.persistenceManager = persistenceManager
        self.jobQueueContext = jobQueueContext
    }
    
    /// Executes a set of tool calls and saves results to persistence.
    /// Returns true if a topic change was triggered.
    public func handleToolCalls(
        _ toolCalls: [ToolCall],
        assistantMsgId: UUID
    ) async throws -> Bool {
        logger.info("Executing \(toolCalls.count) tool calls")
        
        let toolResults = await toolExecutor.executeAll(toolCalls)
        
        for toolResult in toolResults {
            do {
                try await persistenceManager.addMessage(
                    role: .tool,
                    content: toolResult.content,
                    parentId: assistantMsgId
                )
            } catch {
                logger.error("Failed to save tool result: \(error.localizedDescription)")
            }
        }
        
        return toolCalls.contains(where: { $0.name == "mark_topic_change" })
    }
    
    /// Checks for and dequeues the next job from the queue if auto-dequeue is enabled.
    /// Returns a synthetic user message if a job was dequeued.
    public func autoDequeueNextJob() async -> Message? {
        guard let hasPending = try? await jobQueueContext.hasPendingJobs(), hasPending,
              let nextJob = try? await jobQueueContext.dequeueNext() else {
            return nil
        }
        
        logger.info("Auto-dequeueing job: \(nextJob.title)")
        
        let jobPrompt = """
            [Auto-Dequeued Task]
            **\(nextJob.title)**
            \(nextJob.description ?? "")

            Please complete this task.
            """
            
        return Message(content: jobPrompt, role: .user)
    }
}

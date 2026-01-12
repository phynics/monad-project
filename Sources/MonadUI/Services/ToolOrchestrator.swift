import Foundation
import MonadCore
import OSLog

/// Delegate for handling sensitive operations that require user confirmation.
@MainActor
public protocol SQLConfirmationDelegate: AnyObject {
    func requestConfirmation(for sql: String) async -> Bool
}

/// Orchestrates tool execution and integrates results back into the conversation state.
@MainActor
public final class ToolOrchestrator {
    public weak var delegate: SQLConfirmationDelegate?
    
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
        
        // Filter for SQL tool calls and check for sensitivity
        for call in toolCalls where call.name == "execute_sql" {
            if let sql = call.arguments["sql"]?.value as? String {
                if let sqlTool = toolExecutor.getTool(id: "execute_sql") as? ExecuteSQLTool {
                    if sqlTool.isSensitive(sql: sql) {
                        if let delegate = delegate {
                            let confirmed = await delegate.requestConfirmation(for: sql)
                            if !confirmed {
                                // User cancelled. Save a 'cancelled' message and return.
                                try await persistenceManager.addMessage(
                                    role: .tool,
                                    content: "Error: Operation cancelled by user.",
                                    parentId: assistantMsgId
                                )
                                return false
                            }
                        }
                    }
                }
            }
        }
        
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
    public func autoDequeueNextJob() -> Message? {
        guard jobQueueContext.hasPendingJobs, let nextJob = jobQueueContext.dequeueNext() else {
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

import Foundation

/// Protocol defining the behavior of an agent in the system
public protocol AgentProtocol: Actor, Sendable {
    /// Unique identifier for the agent
    nonisolated var id: String { get }
    
    /// Display name of the agent
    nonisolated var name: String { get }
    
    /// Description of the agent's capabilities
    nonisolated var description: String { get }
    
    /// Execute a job
    /// - Parameters:
    ///   - job: The job to execute
    ///   - session: The session context
    ///   - toolExecutor: The executor for running tools
    ///   - contextManager: The manager for RAG context (optional)
    func execute(
        job: Job,
        session: ConversationSession,
        toolExecutor: ToolExecutor,
        contextManager: ContextManager?
    ) async
}

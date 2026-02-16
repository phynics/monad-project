import MonadShared
import Foundation

/// Protocol defining the behavior of an agent in the system
public protocol AgentProtocol: Sendable {
    /// Full manifest of agent metadata
    var manifest: AgentManifest { get }
    
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

extension AgentProtocol {
    /// Unique identifier for the agent
    public nonisolated var id: String { manifest.id }
    
    /// Display name of the agent
    public nonisolated var name: String { manifest.name }
    
    /// Description of the agent's capabilities
    public nonisolated var description: String { manifest.description }
}

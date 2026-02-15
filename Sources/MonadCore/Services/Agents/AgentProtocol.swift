import Foundation

/// Structured metadata for an agent
public struct AgentManifest: Codable, Sendable, Equatable {
    /// Unique identifier for the agent
    public let id: String
    
    /// Display name of the agent
    public let name: String
    
    /// Description of the agent's purpose and logic
    public let description: String
    
    /// Specific capabilities or domains of expertise (e.g. ["coding", "research", "summarization"])
    public let capabilities: [String]
    
    /// Icons or other UI hints (optional)
    public let metadata: [String: String]

    public init(
        id: String,
        name: String,
        description: String,
        capabilities: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.capabilities = capabilities
        self.metadata = metadata
    }
}

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

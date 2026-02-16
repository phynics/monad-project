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

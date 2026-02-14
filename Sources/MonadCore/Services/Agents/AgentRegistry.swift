import Foundation
import Logging

/// Registry for managing available agents in the system
public actor AgentRegistry {
    private var agents: [String: any AgentProtocol] = [:]
    private let logger = Logger(label: "com.monad.agent-registry")
    
    public init() {}
    
    /// Register a new agent
    /// - Parameter agent: The agent to register
    public func register(_ agent: any AgentProtocol) {
        if agents[agent.id] != nil {
            logger.warning("Overwriting existing agent with id: \(agent.id)")
        }
        agents[agent.id] = agent
        logger.info("Registered agent: \(agent.id) (\(agent.name))")
    }
    
    /// Get an agent by ID
    /// - Parameter id: The agent ID
    /// - Returns: The agent if found, nil otherwise
    public func getAgent(id: String) -> (any AgentProtocol)? {
        return agents[id]
    }
    
    /// List all registered agents
    /// - Returns: Array of agent metadata (id, name, description)
    public func listAgents() -> [(id: String, name: String, description: String)] {
        return agents.values.map { ($0.id, $0.name, $0.description) }
            .sorted { $0.id < $1.id }
    }
    
    /// Check if an agent exists
    public func hasAgent(id: String) -> Bool {
        return agents[id] != nil
    }
}

import MonadShared
import Foundation
import Logging
import Dependencies

/// Registry for managing available agents in the system.
/// Now backed by the Persistence Layer (Database).
public actor AgentRegistry {
    @Dependency(\.persistenceService) private var persistence
    private let logger = Logger(label: "com.monad.agent-registry")
    
    public init() {}
    
    /// Get an agent definition by ID from the database
    /// - Parameter id: The agent ID
    /// - Returns: The agent if found, nil otherwise
    public func getAgent(id: String) async -> Agent? {
        do {
            return try await persistence.databaseWriter.read { db in
                try Agent.fetchOne(db, key: id)
            }
        } catch {
            logger.error("Failed to fetch agent \(id): \(error)")
            return nil
        }
    }
    
    /// List all agents defined in the database
    /// - Returns: Array of agents
    public func listAgents() async -> [Agent] {
        do {
            return try await persistence.databaseWriter.read { db in
                try Agent.fetchAll(db)
            }
        } catch {
            logger.error("Failed to list agents: \(error)")
            return []
        }
    }
    
    /// Check if an agent exists in the database
    public func hasAgent(id: String) async -> Bool {
        do {
            return try await persistence.databaseWriter.read { db in
                try Agent.exists(db, key: id)
            }
        } catch {
            return false
        }
    }
}
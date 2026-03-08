import MonadShared
import Foundation
import Logging
import Dependencies

/// Registry for managing available agentTemplates in the system.
/// Now backed by the Persistence Layer (Database).
public actor AgentTemplateRegistry {
    @Dependency(\.agentTemplateStore) private var persistence
    private let logger = Logger.module(named: "agent-registry")

    public init() {}

    /// Get an agent definition by ID from the database
    /// - Parameter id: The agent ID
    /// - Returns: The agent if found, nil otherwise
    public func getAgentTemplate(id: String) async -> AgentTemplate? {
        do {
            // Try fetching by key string (which might handle UUID parsing internally in implementation)
            return try await persistence.fetchAgentTemplate(key: id)
        } catch {
            logger.error("Failed to fetch agent \(id): \(error)")
            return nil
        }
    }

    /// List all agentTemplates defined in the database
    /// - Returns: Array of agentTemplates
    public func listAgentTemplates() async -> [AgentTemplate] {
        do {
            return try await persistence.fetchAllAgentTemplates()
        } catch {
            logger.error("Failed to list agentTemplates: \(error)")
            return []
        }
    }

    /// Check if an agent exists in the database
    public func hasAgentTemplate(id: String) async -> Bool {
        return await persistence.hasAgentTemplate(id: id)
    }
}

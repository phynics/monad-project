import MonadShared
import Foundation
import Logging
import Dependencies

/// Registry for managing available msAgents in the system.
/// Now backed by the Persistence Layer (Database).
public actor MSAgentRegistry {
    @Dependency(\.msAgentStore) private var persistence
    private let logger = Logger.module(named: "agent-registry")

    public init() {}

    /// Get an agent definition by ID from the database
    /// - Parameter id: The agent ID
    /// - Returns: The agent if found, nil otherwise
    public func getMSAgent(id: String) async -> MSAgent? {
        do {
            // Try fetching by key string (which might handle UUID parsing internally in implementation)
            return try await persistence.fetchMSAgent(key: id)
        } catch {
            logger.error("Failed to fetch agent \(id): \(error)")
            return nil
        }
    }

    /// List all msAgents defined in the database
    /// - Returns: Array of msAgents
    public func listMSAgents() async -> [MSAgent] {
        do {
            return try await persistence.fetchAllMSAgents()
        } catch {
            logger.error("Failed to list msAgents: \(error)")
            return []
        }
    }

    /// Check if an agent exists in the database
    public func hasMSAgent(id: String) async -> Bool {
        return await persistence.hasMSAgent(id: id)
    }
}

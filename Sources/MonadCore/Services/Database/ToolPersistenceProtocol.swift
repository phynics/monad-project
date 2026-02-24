/// Protocol for managing tool registrations and routing metadata.

import Foundation

public protocol ToolPersistenceProtocol: Sendable {
    func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws
    func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference]
    func fetchClientTools(clientId: UUID) async throws -> [ToolReference]
    func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID?
    func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String?
}

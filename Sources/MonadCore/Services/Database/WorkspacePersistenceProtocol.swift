import Foundation

public protocol WorkspacePersistenceProtocol: Sendable {
    func saveWorkspace(_ workspace: WorkspaceReference) async throws
    func fetchWorkspace(id: UUID) async throws -> WorkspaceReference?
    func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference?
    func fetchAllWorkspaces() async throws -> [WorkspaceReference]
    func deleteWorkspace(id: UUID) async throws
}

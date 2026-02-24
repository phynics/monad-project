import Foundation
import Dependencies

/// Repository for managing Workspace data persistence and business logic.
public actor WorkspaceRepository {
    @Dependency(\.persistenceService) private var persistenceService

    public init() {}

    /// Creates a new workspace and saves it to persistence.
    public func createWorkspace(
        uri: WorkspaceURI,
        hostType: WorkspaceReference.WorkspaceHostType,
        ownerId: UUID? = nil,
        rootPath: String? = nil,
        metadata: [String: AnyCodable] = [:]
    ) async throws -> WorkspaceReference {
        let workspace = WorkspaceReference(
            uri: uri,
            hostType: hostType,
            ownerId: ownerId,
            rootPath: rootPath,
            metadata: metadata
        )
        try await persistenceService.saveWorkspace(workspace)
        return workspace
    }

    /// Fetches a workspace by its unique identifier.
    public func getWorkspace(id: UUID, includeTools: Bool = true) async throws -> WorkspaceReference? {
        return try await persistenceService.fetchWorkspace(id: id, includeTools: includeTools)
    }

    /// Lists all workspaces.
    public func listWorkspaces() async throws -> [WorkspaceReference] {
        return try await persistenceService.fetchAllWorkspaces()
    }

    /// Deletes a workspace.
    public func deleteWorkspace(id: UUID) async throws {
        try await persistenceService.deleteWorkspace(id: id)
    }

    /// Updates an existing workspace.
    public func updateWorkspace(_ workspace: WorkspaceReference) async throws {
        try await persistenceService.saveWorkspace(workspace)
    }
}

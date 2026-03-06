import MonadShared
import Foundation
import Logging

public actor WorkspaceStore {
    private let persistenceService: any WorkspacePersistenceProtocol
    private let workspaceCreator: any WorkspaceCreating
    private var loadedWorkspaces: [UUID: any WorkspaceProtocol] = [:]
    private let logger = Logger.module(named: "workspace-store")

    public init(
        persistenceService: any WorkspacePersistenceProtocol,
        workspaceCreator: any WorkspaceCreating
    ) async throws {
        self.persistenceService = persistenceService
        self.workspaceCreator = workspaceCreator
        try await loadWorkspaces()
    }

    private func loadWorkspaces() async throws {
        let references = try await persistenceService.fetchAllWorkspaces()

        for reference in references {
            do {
                let workspace = try workspaceCreator.create(from: reference, connectionManager: nil)
                loadedWorkspaces[reference.id] = workspace
            } catch {
                logger.error("Failed to load workspace \(reference.id): \(error)")
            }
        }
    }

    public func getWorkspace(id: UUID) -> (any WorkspaceProtocol)? {
        return loadedWorkspaces[id]
    }

    public func reloadWorkspace(id: UUID) async throws {
        guard let reference = try await persistenceService.fetchWorkspace(id: id) else {
            loadedWorkspaces.removeValue(forKey: id)
            return
        }

        let workspace = try workspaceCreator.create(from: reference, connectionManager: nil)
        loadedWorkspaces[id] = workspace
    }

    public func unloadWorkspace(id: UUID) {
        loadedWorkspaces.removeValue(forKey: id)
    }

    /// Create a new workspace, persist it, and add to the cache
    public func createWorkspace(
        uri: WorkspaceURI,
        hostType: WorkspaceReference.WorkspaceHostType,
        rootPath: String? = nil,
        ownerId: UUID? = nil
    ) async throws -> any WorkspaceProtocol {
        let reference = WorkspaceReference(
            uri: uri,
            hostType: hostType,
            ownerId: ownerId,
            rootPath: rootPath
        )

        try await persistenceService.saveWorkspace(reference)

        let workspace = try workspaceCreator.create(from: reference, connectionManager: nil)
        loadedWorkspaces[reference.id] = workspace
        return workspace
    }

    /// Delete a workspace from both the cache and persistence
    public func deleteWorkspace(id: UUID) async throws {
        loadedWorkspaces.removeValue(forKey: id)
        try await persistenceService.deleteWorkspace(id: id)
    }
}

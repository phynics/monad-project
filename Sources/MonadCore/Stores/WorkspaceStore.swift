import MonadShared
import Foundation
import Logging

public actor WorkspaceStore: Sendable {
    private let persistenceService: any PersistenceServiceProtocol
    private var loadedWorkspaces: [UUID: any WorkspaceProtocol] = [:]
    private let logger = Logger(label: "monad.workspace.store")
    
    public init(persistenceService: any PersistenceServiceProtocol) async throws {
        self.persistenceService = persistenceService
        try await loadWorkspaces()
    }
    
    private func loadWorkspaces() async throws {
        let references = try await persistenceService.fetchAllWorkspaces()
        
        for reference in references {
            do {
                let workspace = try WorkspaceFactory.create(from: reference)
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
        
        let workspace = try WorkspaceFactory.create(from: reference)
        loadedWorkspaces[id] = workspace
    }
    
    public func unloadWorkspace(id: UUID) {
        loadedWorkspaces.removeValue(forKey: id)
    }

    /// Create a new workspace and store it in the database
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
        
        let workspace = try WorkspaceFactory.create(from: reference)
        loadedWorkspaces[reference.id] = workspace
        return workspace
    }
}

import MonadShared
import MonadShared
import Foundation
import GRDB

public actor WorkspaceStore: Sendable {
    private let dbWriter: DatabaseWriter
    private var loadedWorkspaces: [UUID: any WorkspaceProtocol] = [:]
    
    public init(dbWriter: DatabaseWriter) async throws {
        self.dbWriter = dbWriter
        try await loadWorkspaces()
    }
    
    private func loadWorkspaces() async throws {
        let references = try await dbWriter.read { db in
            try WorkspaceReference.fetchAll(db)
        }
        
        for reference in references {
            do {
                let workspace = try WorkspaceFactory.create(from: reference)
                loadedWorkspaces[reference.id] = workspace
            } catch {
                // We don't have a logger here yet, but in a real app we should log this.
                // For now, we just skip it so one bad workspace doesn't prevent startup.
                print("Failed to load workspace \(reference.id): \(error)")
            }
        }
    }
    
    public func getWorkspace(id: UUID) -> (any WorkspaceProtocol)? {
        return loadedWorkspaces[id]
    }
    
    public func reloadWorkspace(id: UUID) async throws {
        let reference = try await dbWriter.read { db in
            try WorkspaceReference.fetchOne(db, key: id)
        }
        
        guard let reference = reference else {
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
        
        try await dbWriter.write { db in
            try reference.insert(db)
        }
        
        let workspace = try WorkspaceFactory.create(from: reference)
        loadedWorkspaces[reference.id] = workspace
        return workspace
    }
}

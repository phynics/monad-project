import MonadShared
import Foundation

/// Factory for resolving WorkspaceReference into a concrete WorkspaceProtocol implementation
public enum WorkspaceFactory {
    
    public static func create(from reference: WorkspaceReference, connectionManager: (any ClientConnectionManagerProtocol)? = nil) throws -> any WorkspaceProtocol {
        switch reference.hostType {
        case .server, .serverSession:
            return try LocalWorkspace(reference: reference)
        case .client:
            guard let cm = connectionManager else {
                throw WorkspaceError.connectionFailed
            }
            return try RemoteWorkspace(reference: reference, connectionManager: cm)
        }
    }
}

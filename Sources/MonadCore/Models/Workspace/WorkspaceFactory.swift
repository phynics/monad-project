import Foundation

/// Factory for resolving WorkspaceReference into a concrete WorkspaceProtocol implementation
public enum WorkspaceFactory {
    
    public static func create(from reference: WorkspaceReference) throws -> any WorkspaceProtocol {
        switch reference.hostType {
        case .server, .serverSession:
            return try LocalWorkspace(reference: reference)
        case .client:
            return try RemoteWorkspace(reference: reference)
        }
    }
}

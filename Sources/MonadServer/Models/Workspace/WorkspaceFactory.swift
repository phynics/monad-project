import MonadCore
import MonadShared
import Foundation

/// Factory for resolving WorkspaceReference into a concrete WorkspaceProtocol implementation.
/// Conforms to `WorkspaceCreating` so it can be injected into MonadCore services.
public struct WorkspaceFactory: WorkspaceCreating {

    public init() {}

    public func create(
        from reference: WorkspaceReference,
        connectionManager: (any ClientConnectionManagerProtocol)?
    ) throws -> any WorkspaceProtocol {
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

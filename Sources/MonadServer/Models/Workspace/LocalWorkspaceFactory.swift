import Foundation
import MonadShared
import PKShared
import PositronicKit

/// Factory for resolving WorkspaceReference into a concrete Workspace implementation.
/// Conforms to PositronicKit's `WorkspaceFactory` protocol so it can be injected into
/// MonadCore services; named `LocalWorkspaceFactory` to avoid colliding with that protocol
/// name once both are in scope.
public struct LocalWorkspaceFactory: WorkspaceFactory {
    private let connectionManager: (any ClientConnectionManagerProtocol)?

    public init(connectionManager: (any ClientConnectionManagerProtocol)? = nil) {
        self.connectionManager = connectionManager
    }

    public func create(from reference: WorkspaceReference) throws -> any Workspace {
        switch reference.location {
        case .runtime, .runtimeTimeline:
            return try LocalWorkspace(reference: reference)
        case .attached:
            guard let connManager = connectionManager else {
                throw WorkspaceError.connectionFailed
            }
            return try RemoteWorkspace(reference: reference, connectionManager: connManager)
        }
    }
}

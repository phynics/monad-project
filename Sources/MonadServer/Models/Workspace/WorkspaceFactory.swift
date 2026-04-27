import Foundation
import PositronicKit
import PKShared

/// Factory for resolving WorkspaceReference into a concrete WorkspaceProtocol implementation.
/// Conforms to `WorkspaceCreating` so it can be injected into MonadCore services.
public struct WorkspaceFactory: WorkspaceCreating {
    private let connectionManager: (any ClientConnectionManagerProtocol)?

    public init(connectionManager: (any ClientConnectionManagerProtocol)? = nil) {
        self.connectionManager = connectionManager
    }

    public func create(from reference: WorkspaceReference) throws -> any WorkspaceProtocol {
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

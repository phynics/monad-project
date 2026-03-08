import Foundation
import MonadShared

/// Domain-specific client for Workspace, Tool, and File operations
public struct MonadWorkspaceClient: Sendable {
    public let client: MonadClient

    public init(client: MonadClient) {
        self.client = client
    }
}

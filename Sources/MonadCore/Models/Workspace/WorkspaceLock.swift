import MonadShared
import Foundation

// MARK: - Workspace Lock

/// Lock held by a session during its generation cycle
public struct WorkspaceLock: Codable, Sendable {
    public let workspaceId: UUID
    public let heldBy: UUID  // Session ID
    public let acquiredAt: Date

    public init(workspaceId: UUID, heldBy: UUID, acquiredAt: Date = Date()) {
        self.workspaceId = workspaceId
        self.heldBy = heldBy
        self.acquiredAt = acquiredAt
    }
}

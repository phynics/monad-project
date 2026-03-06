import MonadShared
import Foundation

// MARK: - Workspace Attachment

/// Represents a workspace attached to a session
public struct WorkspaceAttachment: Codable, Sendable {
    public let workspaceId: UUID
    public let attachedAt: Date

    public init(workspaceId: UUID, attachedAt: Date = Date()) {
        self.workspaceId = workspaceId
        self.attachedAt = attachedAt
    }
}

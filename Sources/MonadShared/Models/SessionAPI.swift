import Foundation
import MonadCore

public struct CreateSessionRequest: Codable, Sendable {
    public let title: String?
    public let primaryWorkspaceId: UUID?

    public init(title: String? = nil, primaryWorkspaceId: UUID? = nil) {
        self.title = title
        self.primaryWorkspaceId = primaryWorkspaceId
    }
}

public struct UpdateSessionTitleRequest: Codable, Sendable {
    public let title: String

    public init(title: String) {
        self.title = title
    }
}

public struct SessionWorkspacesResponse: Codable, Sendable {
    public let primaryWorkspace: WorkspaceReference?
    public let attachedWorkspaces: [WorkspaceReference]

    public init(primaryWorkspace: WorkspaceReference?, attachedWorkspaces: [WorkspaceReference]) {
        self.primaryWorkspace = primaryWorkspace
        self.attachedWorkspaces = attachedWorkspaces
    }
}

public struct SessionResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let isArchived: Bool
    public let tags: [String]
    public let workingDirectory: String?
    public let primaryWorkspaceId: UUID?
    public let attachedWorkspaceIds: [UUID]

    public init(
        id: UUID,
        title: String?,
        createdAt: Date,
        updatedAt: Date,
        isArchived: Bool,
        tags: [String],
        workingDirectory: String?,
        primaryWorkspaceId: UUID?,
        attachedWorkspaceIds: [UUID]
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.tags = tags
        self.workingDirectory = workingDirectory
        self.primaryWorkspaceId = primaryWorkspaceId
        self.attachedWorkspaceIds = attachedWorkspaceIds
    }

    public init(id: UUID, title: String?) {
        self.id = id
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isArchived = false
        self.tags = []
        self.workingDirectory = nil
        self.primaryWorkspaceId = nil
        self.attachedWorkspaceIds = []
    }
}

public struct UpdateSessionRequest: Codable, Sendable {
    public let title: String?
    
    public init(title: String? = nil) {
        self.title = title
    }
}

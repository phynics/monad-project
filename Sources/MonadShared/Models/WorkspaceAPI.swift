import Foundation
import MonadCore

public struct CreateWorkspaceRequest: Codable, Sendable {
    public let uri: String
    public let hostType: WorkspaceReference.WorkspaceHostType
    public let ownerId: UUID?
    public let rootPath: String?
    public let trustLevel: WorkspaceTrustLevel?
    public let tools: [ToolReference]

    public init(
        uri: String,
        hostType: WorkspaceReference.WorkspaceHostType,
        ownerId: UUID?,
        rootPath: String?,
        trustLevel: WorkspaceTrustLevel?,
        tools: [ToolReference] = []
    ) {
        self.uri = uri
        self.hostType = hostType
        self.ownerId = ownerId
        self.rootPath = rootPath
        self.trustLevel = trustLevel
        self.tools = tools
    }
}

public struct RegisterToolRequest: Codable, Sendable {
    public let tool: ToolReference

    public init(tool: ToolReference) {
        self.tool = tool
    }
}

public struct AttachWorkspaceRequest: Codable, Sendable {
    public let workspaceId: UUID
    public let isPrimary: Bool

    public init(workspaceId: UUID, isPrimary: Bool) {
        self.workspaceId = workspaceId
        self.isPrimary = isPrimary
    }
}

public struct UpdateWorkspaceRequest: Codable, Sendable {
    public let rootPath: String?
    public let trustLevel: WorkspaceTrustLevel?

    public init(rootPath: String? = nil, trustLevel: WorkspaceTrustLevel? = nil) {
        self.rootPath = rootPath
        self.trustLevel = trustLevel
    }
}

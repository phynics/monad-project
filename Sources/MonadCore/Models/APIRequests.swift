import Foundation

// MARK: - Workspace API

public struct CreateWorkspaceRequest: Codable, Sendable {
    public let uri: String
    public let hostType: WorkspaceHostType
    public let ownerId: UUID?
    public let rootPath: String?
    public let trustLevel: WorkspaceTrustLevel?

    public init(
        uri: String,
        hostType: WorkspaceHostType,
        ownerId: UUID?,
        rootPath: String?,
        trustLevel: WorkspaceTrustLevel?
    ) {
        self.uri = uri
        self.hostType = hostType
        self.ownerId = ownerId
        self.rootPath = rootPath
        self.trustLevel = trustLevel
    }
}

public struct RegisterToolRequest: Codable, Sendable {
    public let tool: ToolReference

    public init(tool: ToolReference) {
        self.tool = tool
    }
}

// MARK: - Session API

public struct AttachWorkspaceRequest: Codable, Sendable {
    public let workspaceId: UUID
    public let isPrimary: Bool

    public init(workspaceId: UUID, isPrimary: Bool) {
        self.workspaceId = workspaceId
        self.isPrimary = isPrimary
    }
}

public struct SessionWorkspacesResponse: Codable, Sendable {
    public let primaryWorkspaceId: UUID?
    public let attachedWorkspaceIds: [UUID]

    public init(primaryWorkspaceId: UUID?, attachedWorkspaceIds: [UUID]) {
        self.primaryWorkspaceId = primaryWorkspaceId
        self.attachedWorkspaceIds = attachedWorkspaceIds
    }
}

// MARK: - Chat API

public struct ToolOutputSubmission: Codable, Sendable {
    public let toolCallId: String
    public let output: String

    public init(toolCallId: String, output: String) {
        self.toolCallId = toolCallId
        self.output = output
    }
}

public struct ChatRequest: Codable, Sendable {
    public let message: String
    public let toolOutputs: [ToolOutputSubmission]?

    public init(message: String, toolOutputs: [ToolOutputSubmission]? = nil) {
        self.message = message
        self.toolOutputs = toolOutputs
    }
}

public struct ChatResponse: Codable, Sendable {
    public let response: String

    public init(response: String) {
        self.response = response
    }
}

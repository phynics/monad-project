import Foundation

// MARK: - Workspace API

public struct CreateWorkspaceRequest: Codable, Sendable {
    public let uri: String
    public let hostType: WorkspaceHostType
    public let ownerId: UUID?
    public let rootPath: String?
    public let trustLevel: WorkspaceTrustLevel?
    public let tools: [ToolReference]

    public init(
        uri: String,
        hostType: WorkspaceHostType,
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

// MARK: - Session API

public struct CreateSessionRequest: Codable, Sendable {
    public let title: String?
    public let primaryWorkspaceId: UUID?
    public let persona: String?

    public init(title: String? = nil, primaryWorkspaceId: UUID? = nil, persona: String? = nil) {
        self.title = title
        self.primaryWorkspaceId = primaryWorkspaceId
        self.persona = persona
    }
}

public struct UpdatePersonaRequest: Codable, Sendable {
    public let persona: String

    public init(persona: String) {
        self.persona = persona
    }
}

public struct UpdateSessionTitleRequest: Codable, Sendable {
    public let title: String

    public init(title: String) {
        self.title = title
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

/// A delta from a streaming chat response
public struct ChatDelta: Sendable, Codable {
    public let content: String?
    public let thought: String?
    public let toolCalls: [ToolCallDelta]?
    public let metadata: ChatMetadata?
    public let error: String?
    public let isDone: Bool

    public init(
        content: String? = nil,
        thought: String? = nil,
        toolCalls: [ToolCallDelta]? = nil,
        metadata: ChatMetadata? = nil,
        error: String? = nil,
        isDone: Bool = false
    ) {
        self.content = content
        self.thought = thought
        self.toolCalls = toolCalls
        self.metadata = metadata
        self.error = error
        self.isDone = isDone
    }
}

/// A delta for a tool call in a streaming response
public struct ToolCallDelta: Sendable, Codable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let arguments: String?

    public init(index: Int, id: String? = nil, name: String? = nil, arguments: String? = nil) {
        self.index = index
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Metadata about the context used for a chat response
public struct ChatMetadata: Sendable, Codable {
    public let memories: [UUID]
    public let files: [String]

    public init(memories: [UUID] = [], files: [String] = []) {
        self.memories = memories
        self.files = files
    }
}

// MARK: - Session API

public struct SessionResponse: Codable, Sendable, Identifiable {
    public let id: UUID
    public let title: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let isArchived: Bool
    public let tags: [String]
    public let workingDirectory: String?
    public let persona: String?
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
        persona: String?,
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
        self.persona = persona
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
        self.persona = nil
        self.primaryWorkspaceId = nil
        self.attachedWorkspaceIds = []
    }
}

// MARK: - Tool API

public struct ToolInfo: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let isEnabled: Bool
    public let source: String?

    public init(
        id: String, name: String, description: String, isEnabled: Bool = true, source: String? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isEnabled = isEnabled
        self.source = source
    }
}

// MARK: - Note API

public struct CreateNoteRequest: Codable, Sendable {
    public let title: String
    public let content: String

    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}

public struct UpdateNoteRequest: Codable, Sendable {
    public let title: String?
    public let content: String?

    public init(title: String? = nil, content: String? = nil) {
        self.title = title
        self.content = content
    }
}

// MARK: - Memory API

public struct MemorySearchRequest: Codable, Sendable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

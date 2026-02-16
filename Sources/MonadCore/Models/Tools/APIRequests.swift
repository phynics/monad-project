import Foundation

// MARK: - Workspace API

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

// MARK: - Session API

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

public struct AttachWorkspaceRequest: Codable, Sendable {
    public let workspaceId: UUID
    public let isPrimary: Bool

    public init(workspaceId: UUID, isPrimary: Bool) {
        self.workspaceId = workspaceId
        self.isPrimary = isPrimary
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
    public let clientId: UUID?

    public init(message: String, toolOutputs: [ToolOutputSubmission]? = nil, clientId: UUID? = nil) {
        self.message = message
        self.toolOutputs = toolOutputs
        self.clientId = clientId
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


// MARK: - Memory API

public struct CreateMemoryRequest: Codable, Sendable {
    public let content: String
    public let title: String?
    public let tags: [String]?
    
    public init(content: String, title: String? = nil, tags: [String]? = nil) {
        self.content = content
        self.title = title
        self.tags = tags
    }
}

public struct MemorySearchRequest: Codable, Sendable {
    public let query: String
    public let limit: Int?

    public init(query: String, limit: Int? = nil) {
        self.query = query
        self.limit = limit
    }
}

public struct UpdateMemoryRequest: Codable, Sendable {
    public let content: String?
    public let tags: [String]?

    public init(content: String? = nil, tags: [String]? = nil) {
        self.content = content
        self.tags = tags
    }
}

// MARK: - Common API Types

public struct PaginationRequest: Codable, Sendable {
    public let page: Int
    public let perPage: Int

    public init(page: Int = 1, perPage: Int = 20) {
        self.page = max(1, page)
        self.perPage = max(1, min(100, perPage))
    }
}

public struct PaginationMetadata: Codable, Sendable {
    public let page: Int
    public let perPage: Int
    public let totalItems: Int
    public let totalPages: Int

    public init(page: Int, perPage: Int, totalItems: Int) {
        self.page = page
        self.perPage = perPage
        self.totalItems = totalItems
        self.totalPages = Int(ceil(Double(totalItems) / Double(perPage)))
    }
}

public struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let metadata: PaginationMetadata

    public init(items: [T], metadata: PaginationMetadata) {
        self.items = items
        self.metadata = metadata
    }
}

public struct APIErrorDetail: Codable, Sendable {
    public let code: String
    public let message: String
    public let details: [String: String]?

    public init(code: String, message: String, details: [String: String]? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

public struct APIErrorResponse: Codable, Sendable {
    public let error: APIErrorDetail

    public init(error: APIErrorDetail) {
        self.error = error
    }
}

public struct UpdateSessionRequest: Codable, Sendable {
    public let title: String?
    
    public init(title: String? = nil) {
        self.title = title
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


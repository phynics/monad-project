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

/// The type of discrete lifecycle event in the chat stream
public enum StreamEventType: String, Sendable, Codable {
    case generationContext
    case delta
    case thought
    case thoughtCompleted
    case toolCall
    case toolExecution
    case generationCompleted
    case streamCompleted
    case error
}

/// A delta or lifecycle event from a streaming chat response
public struct ChatDelta: Sendable, Codable {
    public let type: StreamEventType
    
    // Payloads
    public let content: String?
    public let thought: String?
    public let toolCalls: [ToolCallDelta]?
    public let toolExecution: ToolExecutionDelta?
    public let metadata: ChatMetadata?
    public let responseMetadata: APIMetadataDelta?
    public let error: String?

    public init(
        type: StreamEventType,
        content: String? = nil,
        thought: String? = nil,
        toolCalls: [ToolCallDelta]? = nil,
        toolExecution: ToolExecutionDelta? = nil,
        metadata: ChatMetadata? = nil,
        responseMetadata: APIMetadataDelta? = nil,
        error: String? = nil
    ) {
        self.type = type
        self.content = content
        self.thought = thought
        self.toolCalls = toolCalls
        self.toolExecution = toolExecution
        self.metadata = metadata
        self.responseMetadata = responseMetadata
        self.error = error
    }
}

public struct APIMetadataDelta: Equatable, Sendable, Codable {
    public var model: String?
    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?
    public var finishReason: String?
    public var systemFingerprint: String?
    public var duration: TimeInterval?
    public var tokensPerSecond: Double?

    public init(
        model: String? = nil, promptTokens: Int? = nil, completionTokens: Int? = nil,
        totalTokens: Int? = nil, finishReason: String? = nil, systemFingerprint: String? = nil,
        duration: TimeInterval? = nil, tokensPerSecond: Double? = nil
    ) {
        self.model = model
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.finishReason = finishReason
        self.systemFingerprint = systemFingerprint
        self.duration = duration
        self.tokensPerSecond = tokensPerSecond
    }
}

public struct ToolExecutionDelta: Sendable, Codable {
    public let toolCallId: String
    public let status: String // "attempting", "success", "failure"
    public let name: String?
    public let target: String?
    public let result: String?

    public init(toolCallId: String, status: String, name: String? = nil, target: String? = nil, result: String? = nil) {
        self.toolCallId = toolCallId
        self.status = status
        self.name = name
        self.target = target
        self.result = result
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

public struct PruneMemoriesRequest: Codable, Sendable {
    public let query: String?
    public let days: Int?
    public let dryRun: Bool

    public init(query: String? = nil, days: Int? = nil, dryRun: Bool = false) {
        self.query = query
        self.days = days
        self.dryRun = dryRun
    }
}

public struct PruneSessionRequest: Codable, Sendable {
    public let days: Int
    public let excludedSessionIds: [UUID]
    public let dryRun: Bool

    public init(days: Int, excludedSessionIds: [UUID] = [], dryRun: Bool = false) {
        self.days = days
        self.excludedSessionIds = excludedSessionIds
        self.dryRun = dryRun
    }
}

public struct PruneMessagesRequest: Codable, Sendable {
    public let days: Int
    public let dryRun: Bool

    public init(days: Int, dryRun: Bool = false) {
        self.days = days
        self.dryRun = dryRun
    }
}

public struct PruneResponse: Codable, Sendable {
    public let count: Int
    public let dryRun: Bool

    public init(count: Int, dryRun: Bool) {
        self.count = count
        self.dryRun = dryRun
    }
}

// MARK: - Job API

public struct AddJobRequest: Codable, Sendable {
    public let title: String
    public let description: String?
    public let priority: Int
    public let agentId: String?
    public let parentId: UUID?

    public init(
        title: String,
        description: String? = nil,
        priority: Int = 0,
        agentId: String? = nil,
        parentId: UUID? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.agentId = agentId
        self.parentId = parentId
    }
}

public struct ClientRegistrationRequest: Codable, Sendable {
    public let hostname: String
    public let displayName: String
    public let platform: String
    public let tools: [ToolReference]

    public init(hostname: String, displayName: String, platform: String, tools: [ToolReference] = []) {
        self.hostname = hostname
        self.displayName = displayName
        self.platform = platform
        self.tools = tools
    }
}

public struct ClientRegistrationResponse: Codable, Sendable {
    public let client: ClientIdentity
    public let defaultWorkspace: WorkspaceReference

    public init(client: ClientIdentity, defaultWorkspace: WorkspaceReference) {
        self.client = client
        self.defaultWorkspace = defaultWorkspace
    }
}
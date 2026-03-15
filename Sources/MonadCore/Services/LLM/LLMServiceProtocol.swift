import Foundation
import MonadPrompt
import MonadShared
import OpenAI

// MARK: - Request / Result Types

/// Groups the parameters for a high-level LLM chat stream request.
public struct LLMChatRequest: Sendable {
    public let userQuery: String
    public let contextNotes: [ContextFile]
    public let memories: [Memory]
    public let chatHistory: [Message]
    public let tools: [AnyTool]
    public let workspaces: [WorkspaceReference]
    public let primaryWorkspace: WorkspaceReference?
    public let clientName: String?
    public let systemInstructions: String?
    public let responseFormat: ChatQuery.ResponseFormat?
    public let useFastModel: Bool

    public init(
        userQuery: String,
        contextNotes: [ContextFile] = [],
        memories: [Memory] = [],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil,
        useFastModel: Bool = false
    ) {
        self.userQuery = userQuery
        self.contextNotes = contextNotes
        self.memories = memories
        self.chatHistory = chatHistory
        self.tools = tools
        self.workspaces = workspaces
        self.primaryWorkspace = primaryWorkspace
        self.clientName = clientName
        self.systemInstructions = systemInstructions
        self.responseFormat = responseFormat
        self.useFastModel = useFastModel
    }
}

/// The result of a high-level LLM chat stream request.
public struct LLMStreamResult: Sendable {
    public let stream: AsyncThrowingStream<ChatStreamResult, Error>
    public let rawPrompt: String
    public let structuredContext: [String: String]

    public init(
        stream: AsyncThrowingStream<ChatStreamResult, Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        self.stream = stream
        self.rawPrompt = rawPrompt
        self.structuredContext = structuredContext
    }
}

/// The result of building a prompt (messages + debug info).
public struct LLMPromptResult: Sendable {
    public let messages: [ChatQuery.ChatCompletionMessageParam]
    public let rawPrompt: String
    public let structuredContext: [String: String]

    public init(
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        self.messages = messages
        self.rawPrompt = rawPrompt
        self.structuredContext = structuredContext
    }
}

/// Groups the parameters for building a prompt or context.
public struct LLMPromptRequest: Sendable {
    public let userQuery: String
    public let contextNotes: [ContextFile]
    public let memories: [Memory]
    public let chatHistory: [Message]
    public let tools: [AnyTool]
    public let workspaces: [WorkspaceReference]
    public let primaryWorkspace: WorkspaceReference?
    public let clientName: String?
    public let systemInstructions: String?

    public init(
        userQuery: String,
        contextNotes: [ContextFile] = [],
        memories: [Memory] = [],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String? = nil
    ) {
        self.userQuery = userQuery
        self.contextNotes = contextNotes
        self.memories = memories
        self.chatHistory = chatHistory
        self.tools = tools
        self.workspaces = workspaces
        self.primaryWorkspace = primaryWorkspace
        self.clientName = clientName
        self.systemInstructions = systemInstructions
    }
}

/// Parsed endpoint components.
public struct EndpointComponents: Sendable {
    public let host: String
    public let port: Int
    public let scheme: String

    public init(host: String, port: Int, scheme: String) {
        self.host = host
        self.port = port
        self.scheme = scheme
    }
}

// MARK: - Protocol

/// Protocol for LLM Service to enable mocking and isolation
public protocol LLMServiceProtocol: HealthCheckable {
    var isConfigured: Bool { get async }
    var configuration: LLMConfiguration { get async }

    // Configuration Management
    func loadConfiguration() async
    func updateConfiguration(_ config: LLMConfiguration) async throws
    func clearConfiguration() async
    func restoreFromBackup() async throws
    func exportConfiguration() async throws -> Data
    func importConfiguration(from data: Data) async throws

    // Core LLM Interaction
    func sendMessage(_ content: String) async throws -> String
    func sendMessage(
        _ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool
    ) async throws -> String

    func chatStreamWithContext(_ request: LLMChatRequest) async -> LLMStreamResult

    /// Stream chat response from a prepared list of messages (low-level)
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error>

    func buildPrompt(_ request: LLMPromptRequest) async -> LLMPromptResult

    /// Build a prompt object using the new ContextBuilder system
    func buildContext(
        _ request: LLMPromptRequest,
        agentInstance: AgentInstance?,
        timeline: Timeline?,
        extensionSections: [any ContextSection]
    ) async -> Prompt

    // Utilities
    func generateTags(for text: String) async throws -> [String]
    func generateTitle(for messages: [Message]) async throws -> String
    func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws
        -> [String: Double]
    func fetchAvailableModels() async throws -> [String]?
}

// MARK: - Default Implementations

public extension LLMServiceProtocol {
    /// Convenience overload with no extension sections.
    func buildContext(
        _ request: LLMPromptRequest,
        agentInstance: AgentInstance? = nil,
        timeline: Timeline? = nil
    ) async -> Prompt {
        await buildContext(
            request,
            agentInstance: agentInstance,
            timeline: timeline,
            extensionSections: []
        )
    }
}

import Foundation
import MonadPrompt
import MonadShared
import OpenAI

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

    func chatStreamWithContext(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    )

    /// Stream chat response from a prepared list of messages (low-level)
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error>

    func buildPrompt(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    )

    /// Build a prompt object using the new ContextBuilder system
    func buildContext(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String?,
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
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String?,
        agentInstance: AgentInstance? = nil,
        timeline: Timeline? = nil
    ) async -> Prompt {
        await buildContext(
            userQuery: userQuery,
            contextNotes: contextNotes,
            memories: memories,
            chatHistory: chatHistory,
            tools: tools,
            workspaces: workspaces,
            primaryWorkspace: primaryWorkspace,
            clientName: clientName,
            systemInstructions: systemInstructions,
            agentInstance: agentInstance,
            timeline: timeline,
            extensionSections: []
        )
    }
}

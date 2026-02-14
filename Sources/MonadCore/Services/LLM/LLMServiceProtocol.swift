import Foundation
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
        tools: [any Tool],
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
        tools: [any Tool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    )

    // Utilities
    func generateTags(for text: String) async throws -> [String]
    func generateTitle(for messages: [Message]) async throws -> String
    func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws
        -> [String: Double]
    func fetchAvailableModels() async throws -> [String]?
}

import Foundation
import OpenAI

/// Protocol for LLM Service to enable mocking and isolation
@MainActor
public protocol LLMServiceProtocol: Sendable {
    var isConfigured: Bool { get }
    var configuration: LLMConfiguration { get }
    
    func sendMessage(_ content: String) async throws -> String
    
    func chatStreamWithContext(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [Tool],
        systemInstructions: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>, 
        rawPrompt: String,
        structuredContext: [String: String]
    )
    
    func buildPrompt(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [Tool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    )
    
    func generateTags(for text: String) async throws -> [String]
    func generateTitle(for messages: [Message]) async throws -> String
    func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws -> [String: Double]
}

/// Protocol for Persistence Service to enable mocking and isolation
public protocol PersistenceServiceProtocol: Sendable {
    func fetchAlwaysAppendNotes() async throws -> [Note]
    func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)]
    func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory]
    func fetchMemory(id: UUID) async throws -> Memory?
    func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws
    
    func saveMessage(_ message: ConversationMessage) async throws
    func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage]
    func deleteMessages(for sessionId: UUID) async throws
    
    func saveSession(_ session: ConversationSession) async throws
    func fetchSession(id: UUID) async throws -> ConversationSession?
    func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession]
    func deleteSession(id: UUID) async throws
}

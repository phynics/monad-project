import Foundation
import GRDB
import OpenAI

/// Protocol for LLM Service to enable mocking and isolation
public protocol LLMServiceProtocol: Sendable {
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
        documents: [DocumentContext],
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
        documents: [DocumentContext],
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

/// Protocol for Persistence Service to enable mocking and isolation
public protocol PersistenceServiceProtocol: Sendable {
    var databaseWriter: DatabaseWriter { get }

    // Memories
    func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID
    func fetchMemory(id: UUID) async throws -> Memory?
    func fetchAllMemories() async throws -> [Memory]
    func searchMemories(query: String) async throws -> [Memory]
    func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(
        memory: Memory, similarity: Double
    )]
    func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory]
    func deleteMemory(id: UUID) async throws
    func updateMemory(_ memory: Memory) async throws
    func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws
    func vacuumMemories(threshold: Double) async throws -> Int


    // Messages
    func saveMessage(_ message: ConversationMessage) async throws
    func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage]
    func deleteMessages(for sessionId: UUID) async throws

    // Sessions
    func saveSession(_ session: ConversationSession) async throws
    func fetchSession(id: UUID) async throws -> ConversationSession?
    func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession]
    func deleteSession(id: UUID) async throws
    // searchArchivedSessions moved to MonadServerCore
    // Prune methods moved to MonadServerCore

    // Jobs
    func saveJob(_ job: Job) async throws
    func fetchJob(id: UUID) async throws -> Job?
    func fetchAllJobs() async throws -> [Job]
    func deleteJob(id: UUID) async throws

    // RAW SQL Support
    func executeRaw(sql: String, arguments: [DatabaseValue]) async throws -> [[String: AnyCodable]]

    // Database Management
    func resetDatabase() async throws
}

/// Delegate for requesting user confirmation for sensitive operations
public protocol SQLConfirmationDelegate: AnyObject, Sendable {
    /// Request confirmation for a sensitive SQL operation
    /// - Parameter sql: The SQL command to be executed
    /// - Returns: True if user approved, false otherwise
    func requestConfirmation(for sql: String) async -> Bool
}

import Foundation
import GRDB
import MonadCore
import OpenAI

final class MockEmbeddingService: EmbeddingService, @unchecked Sendable {
    var mockEmbedding: [Double] = [0.1, 0.2, 0.3]
    var lastInput: String?
    var useDistinctEmbeddings: Bool = false

    func generateEmbedding(for text: String) async throws -> [Double] {
        lastInput = text
        if useDistinctEmbeddings {
            let hash = abs(text.hashValue)
            var vector: [Double] = []
            for i in 1...16 {
                vector.append(Double((hash / (i * i)) % 100) / 100.0)
            }
            return VectorMath.normalize(vector)
        }
        return mockEmbedding
    }

    func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
        if useDistinctEmbeddings {
            return try await withThrowingTaskGroup(of: [Double].self) { group in
                for text in texts {
                    group.addTask { try await self.generateEmbedding(for: text) }
                }
                var results: [[Double]] = []
                for try await res in group {
                    results.append(res)
                }
                return results
            }
        }
        return texts.map { _ in mockEmbedding }
    }
}

final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    var nextResponse: String = ""
    var nextResponses: [String] = []
    var lastMessages: [ChatQuery.ChatCompletionMessageParam] = []
    var shouldThrowError: Bool = false

    // Support for tool calls in stream - use dictionaries to avoid type issues
    var nextToolCalls: [[[String: Any]]] = []

    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        lastMessages = messages

        if shouldThrowError {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "MockError", code: 1, userInfo: nil))
            }
        }

        let response = nextResponses.isEmpty ? nextResponse : nextResponses.removeFirst()
        let toolCalls = nextToolCalls.isEmpty ? nil : nextToolCalls.removeFirst()

        return AsyncThrowingStream { continuation in
            var delta: [String: Any] = [
                "role": "assistant",
                "content": response
            ]

            if let tc = toolCalls {
                delta["tool_calls"] = tc
            }

            let jsonDict: [String: Any] = [
                "id": "mock",
                "object": "chat.completion.chunk",
                "created": Date().timeIntervalSince1970,
                "model": "mock-model",
                "choices": [
                    [
                        "index": 0,
                        "delta": delta,
                        "finish_reason": toolCalls != nil ? "tool_calls" : "stop"
                    ]
                ]
            ]

            do {
                let data = try JSONSerialization.data(withJSONObject: jsonDict)
                let result = try JSONDecoder().decode(ChatStreamResult.self, from: data)
                continuation.yield(result)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?) async throws
        -> String {
        if shouldThrowError {
            throw NSError(
                domain: "MockError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
        }
        lastMessages = [.user(.init(content: .string(content)))]
        return nextResponse
    }
}

final class MockLLMService: LLMServiceProtocol, @unchecked Sendable {
    var isConfigured: Bool = true
    var configuration: LLMConfiguration = .openAI
    var nextResponse: String = ""
    var nextTags: [String] = []

    func loadConfiguration() async {}
    func updateConfiguration(_ config: LLMConfiguration) async throws {
        self.configuration = config
    }
    func clearConfiguration() async {
        isConfigured = false
    }
    func restoreFromBackup() async throws {}
    func exportConfiguration() async throws -> Data { return Data() }
    func importConfiguration(from data: Data) async throws {}

    func sendMessage(_ content: String) async throws -> String {
        return nextResponse
    }

    func sendMessage(
        _ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool
    ) async throws -> String {
        return nextResponse
    }

    func chatStreamWithContext(
        userQuery: String,
        contextNotes: [ContextFile],
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [any MonadCore.Tool],
        systemInstructions: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
            continuation.finish()
        }
        return (stream, "mock prompt", [:])
    }

    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
            continuation.finish()
        }
        return stream
    }

    func buildPrompt(
        userQuery: String,
        contextNotes: [ContextFile],
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [any MonadCore.Tool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return ([], "mock prompt", [:])
    }

    func generateTags(for text: String) async throws -> [String] {
        return nextTags
    }

    func generateTitle(for messages: [Message]) async throws -> String {
        return "Mock Title"
    }

    func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws
        -> [String: Double] {
        return [:]
    }

    func fetchAvailableModels() async throws -> [String]? {
        return ["mock-model"]
    }
}

final class MockPersistenceService: PersistenceServiceProtocol, @unchecked Sendable {
    var databaseWriter: DatabaseWriter = try! DatabaseQueue()
    var memories: [Memory] = []
    var searchResults: [(memory: Memory, similarity: Double)] = []
    var messages: [ConversationMessage] = []
    var sessions: [ConversationSession] = []
    var jobs: [Job] = []

    // Memories
    func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID {
        memories.append(memory)
        return memory.id
    }

    func fetchMemory(id: UUID) async throws -> Memory? {
        return memories.first(where: { $0.id == id })
    }

    func fetchAllMemories() async throws -> [Memory] {
        return memories
    }

    func searchMemories(query: String) async throws -> [Memory] {
        return memories.filter { $0.title.contains(query) || $0.content.contains(query) }
    }

    func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(
        memory: Memory, similarity: Double
    )] {
        return searchResults
    }

    func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] {
        return memories.filter { memory in
            !Set(memory.tagArray).intersection(tags).isEmpty
        }
    }

    func deleteMemory(id: UUID) async throws {
        memories.removeAll(where: { $0.id == id })
    }

    func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            var memory = memories[index]
            if let data = try? JSONEncoder().encode(newEmbedding) {
                memory.embedding = String(data: data, encoding: .utf8) ?? ""
                memories[index] = memory
            }
        }
    }

    func vacuumMemories(threshold: Double) async throws -> Int {
        return 0
    }

    // Messages
    func saveMessage(_ message: ConversationMessage) async throws {
        messages.append(message)
    }

    func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] {
        return messages.filter { $0.sessionId == sessionId }
    }

    func deleteMessages(for sessionId: UUID) async throws {
        messages.removeAll(where: { $0.sessionId == sessionId })
    }

    // Sessions
    func saveSession(_ session: ConversationSession) async throws {
        sessions.append(session)
    }

    func fetchSession(id: UUID) async throws -> ConversationSession? {
        return sessions.first(where: { $0.id == id })
    }

    func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession] {
        if includeArchived {
            return sessions
        } else {
            return sessions.filter { !$0.isArchived }
        }
    }

    func deleteSession(id: UUID) async throws {
        sessions.removeAll(where: { $0.id == id })
    }

    func searchArchivedSessions(query: String) async throws -> [ConversationSession] {
        return sessions.filter { $0.isArchived && $0.title.contains(query) }
    }

    func searchArchivedSessions(matchingAnyTag tags: [String]) async throws -> [ConversationSession] {
        return sessions.filter { session in
            session.isArchived && !Set(session.tagArray).intersection(tags).isEmpty
        }
    }

    // Jobs
    func saveJob(_ job: Job) async throws {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
    }

    func fetchJob(id: UUID) async throws -> Job? {
        return jobs.first(where: { $0.id == id })
    }

    func fetchAllJobs() async throws -> [Job] {
        return jobs
    }

    func deleteJob(id: UUID) async throws {
        jobs.removeAll(where: { $0.id == id })
    }

    // MARK: - Prune
    func pruneMemories(matching query: String, dryRun: Bool) async throws -> Int {
        if dryRun {
            return memories.filter { $0.title.contains(query) || $0.content.contains(query) }.count
        }
        let countBefore = memories.count
        memories.removeAll { $0.title.contains(query) || $0.content.contains(query) }
        return countBefore - memories.count
    }

    func pruneSessions(olderThan timeInterval: TimeInterval, excluding: [UUID] = [], dryRun: Bool)
        async throws
        -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        if dryRun {
            return sessions.filter { session in
                !session.isArchived && session.updatedAt < cutoffDate
                    && !excluding.contains(session.id)
            }.count
        }
        let countBefore = sessions.count
        sessions.removeAll { session in
            !session.isArchived && session.updatedAt < cutoffDate && !excluding.contains(session.id)
        }
        return countBefore - sessions.count
    }

    func pruneMessages(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        if dryRun {
            return messages.filter { $0.timestamp < cutoffDate }.count
        }
        let countBefore = messages.count
        messages.removeAll { $0.timestamp < cutoffDate }
        return countBefore - messages.count
    }

    // RAW SQL Support
    func executeRaw(sql: String, arguments: [DatabaseValue]) async throws -> [[String: AnyCodable]] {
        // Simple mock implementation: return an error if it looks like a deletion we should block
        if sql.lowercased().contains("delete from note") {
            throw NSError(
                domain: "SQLite", code: 19,
                userInfo: [NSLocalizedDescriptionKey: "Notes cannot be deleted"])
        }
        return []
    }

    // Database Management
    func resetDatabase() async throws {
        memories.removeAll()
        messages.removeAll()
        sessions.removeAll()
        jobs.removeAll()
    }
}

import Foundation
import MonadCore
import OpenAI
import GRDB

public final class MockEmbeddingService: EmbeddingService, @unchecked Sendable {
    public var mockEmbedding: [Double] = [0.1, 0.2, 0.3]
    public var lastInput: String?
    public var useDistinctEmbeddings: Bool = false
    
    public init() {}
    
    public func generateEmbedding(for text: String) async throws -> [Double] {
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
    
    public func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
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

public final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    public var nextResponse: String = ""
    public var nextResponses: [String] = []
    public var lastMessages: [ChatQuery.ChatCompletionMessageParam] = []
    public var shouldThrowError: Bool = false
    
    // Support for tool calls in stream - use dictionaries to avoid type issues
    public var nextToolCalls: [[[String: Any]]] = []
    
    public init() {}
    
    public func chatStream(
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
                        "finish_reason": toolCalls != nil ? "tool_calls" : "stop",
                    ]
                ],
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
    
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?) async throws -> String {
        if shouldThrowError {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
        }
        lastMessages = [.user(.init(content: .string(content)))]
        return nextResponse
    }
}

public final class MockLLMService: LLMServiceProtocol, @unchecked Sendable {
    public var isConfigured: Bool = true
    public var configuration: LLMConfiguration = .openAI
    public var embeddingService: any EmbeddingService = MockEmbeddingService()
    public var nextResponse: String = ""
    public var nextTags: [String] = []
    
    public init() {}
    
    public func loadConfiguration() async {}
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        self.configuration = config
    }
    public func clearConfiguration() async {
        isConfigured = false
    }
    public func restoreFromBackup() async throws {}
    public func exportConfiguration() async throws -> Data { return Data() }
    public func importConfiguration(from data: Data) async throws {}

    public func sendMessage(_ content: String) async throws -> String {
        return nextResponse
    }
    
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool) async throws -> String {
        return nextResponse
    }
    
    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext],
        memories: [Memory],
        databaseDirectory: [TableDirectoryEntry],
        chatHistory: [Message],
        tools: [MonadCore.Tool],
        systemInstructions: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>, 
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let response = nextResponse
        let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
            continuation.yield(.init(
                id: "mock",
                choices: [.mock(index: 0, content: response)],
                created: Date().timeIntervalSince1970,
                model: "mock-model"
            ))
            continuation.finish()
        }
        return (stream, "mock prompt", [:])
    }
    
    public func buildPrompt(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext],
        memories: [Memory],
        databaseDirectory: [TableDirectoryEntry],
        chatHistory: [Message],
        tools: [MonadCore.Tool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return ([], "mock prompt", [:])
    }
    
    public func generateTags(for text: String) async throws -> [String] {
        return nextTags
    }
    
    public func generateTitle(for messages: [Message]) async throws -> String {
        return "Mock Title"
    }
    
    public func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws -> [String: Double] {
        return [:]
    }
    
    public func fetchAvailableModels() async throws -> [String]? {
        return ["mock-model"]
    }
}

public final class MockPersistenceService: PersistenceServiceProtocol, @unchecked Sendable {
    public var memories: [Memory] = []
    public var searchResults: [(memory: Memory, similarity: Double)] = []
    public var messages: [ConversationMessage] = []
    public var sessions: [ConversationSession] = []
    public var notes: [Note] = []
    public var jobs: [Job] = []
    
    public init() {}
    
    // Notes
    public func saveNote(_ note: Note) async throws {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
        }
    }
    
    public func fetchNote(id: UUID) async throws -> Note? {
        return notes.first(where: { $0.id == id })
    }
    
    public func fetchAllNotes() async throws -> [Note] {
        return notes
    }
    
    public func searchNotes(query: String) async throws -> [Note] {
        return notes.filter { $0.name.contains(query) || $0.content.contains(query) }
    }
    
    public func searchNotes(matchingAnyTag tags: [String]) async throws -> [Note] {
        return notes.filter { note in
            !Set(note.tagArray).intersection(tags).isEmpty
        }
    }
    
    public func deleteNote(id: UUID) async throws {
        notes.removeAll(where: { $0.id == id })
    }
    
    // Memories
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID {
        memories.append(memory)
        return memory.id
    }
    
    public func fetchMemory(id: UUID) async throws -> Memory? {
        return memories.first(where: { $0.id == id })
    }
    
    public func fetchAllMemories() async throws -> [Memory] {
        return memories
    }
    
    public func searchMemories(query: String) async throws -> [Memory] {
        return memories.filter { $0.title.contains(query) || $0.content.contains(query) }
    }
    
    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)] {
        return searchResults
    }
    
    public func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] {
        return memories.filter { memory in
            !Set(memory.tagArray).intersection(tags).isEmpty
        }
    }
    
    public func deleteMemory(id: UUID) async throws {
        memories.removeAll(where: { $0.id == id })
    }
    
    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            var memory = memories[index]
            if let data = try? JSONEncoder().encode(newEmbedding) {
                memory.embedding = String(data: data, encoding: .utf8) ?? ""
                memories[index] = memory
            }
        }
    }
    
    public func vacuumMemories(threshold: Double) async throws -> Int {
        return 0
    }
    
    // Messages
    public func saveMessage(_ message: ConversationMessage) async throws {
        messages.append(message)
    }
    
    public func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] {
        return messages.filter { $0.sessionId == sessionId }
    }
    
    public func deleteMessages(for sessionId: UUID) async throws {
        messages.removeAll(where: { $0.sessionId == sessionId })
    }
    
    // Sessions
    public func saveSession(_ session: ConversationSession) async throws {
        sessions.append(session)
    }
    
    public func fetchSession(id: UUID) async throws -> ConversationSession? {
        return sessions.first(where: { $0.id == id })
    }
    
    public func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession] {
        if includeArchived {
            return sessions
        } else {
            return sessions.filter { !$0.isArchived }
        }
    }
    
    public func deleteSession(id: UUID) async throws {
        sessions.removeAll(where: { $0.id == id })
    }
    
    public func searchArchivedSessions(query: String) async throws -> [ConversationSession] {
        return sessions.filter { $0.isArchived && $0.title.contains(query) }
    }
    
    public func searchArchivedSessions(matchingAnyTag tags: [String]) async throws -> [ConversationSession] {
        return sessions.filter { session in
            session.isArchived && !Set(session.tagArray).intersection(tags).isEmpty
        }
    }
    
    // Jobs
    public func saveJob(_ job: Job) async throws {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
    }
    
    public func fetchJob(id: UUID) async throws -> Job? {
        return jobs.first(where: { $0.id == id })
    }
    
    public func fetchAllJobs() async throws -> [Job] {
        return jobs
    }
    
    public func deleteJob(id: UUID) async throws {
        jobs.removeAll(where: { $0.id == id })
    }
    
    // Table Directory
    public func fetchTableDirectory() async throws -> [TableDirectoryEntry] {
        return []
    }
    
    // RAW SQL Support
    public func executeRaw(sql: String, arguments: [DatabaseValue]) async throws -> [[String: AnyCodable]] {
        // Simple mock implementation: return an error if it looks like a deletion we should block
        if sql.lowercased().contains("delete from note") {
            throw NSError(domain: "SQLite", code: 19, userInfo: [NSLocalizedDescriptionKey: "Notes cannot be deleted"])
        }
        return []
    }
    
    // Database Management
    public func resetDatabase() async throws {
        notes.removeAll()
        memories.removeAll()
        messages.removeAll()
        sessions.removeAll()
        jobs.removeAll()
    }
}
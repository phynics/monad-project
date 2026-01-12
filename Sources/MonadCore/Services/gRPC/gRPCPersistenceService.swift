import Foundation
import GRPC
import NIOCore
import SwiftProtobuf
import GRDB

public actor gRPCPersistenceService: PersistenceServiceProtocol {
    private let client: MonadSessionServiceAsyncClient
    private let noteClient: MonadNoteServiceAsyncClient
    private let memoryClient: MonadMemoryServiceAsyncClient
    private let jobClient: MonadJobServiceAsyncClient
    
    public init(channel: GRPCChannel) {
        self.client = MonadSessionServiceAsyncClient(channel: channel)
        self.noteClient = MonadNoteServiceAsyncClient(channel: channel)
        self.memoryClient = MonadMemoryServiceAsyncClient(channel: channel)
        self.jobClient = MonadJobServiceAsyncClient(channel: channel)
    }
    
    // MARK: - Sessions
    
    public func saveSession(_ session: ConversationSession) async throws {
        _ = try await client.updateSession(session.toProto())
    }
    
    public func fetchSession(id: UUID) async throws -> ConversationSession? {
        var request = MonadFetchSessionRequest()
        request.id = id.uuidString
        let proto = try await client.fetchSession(request)
        return ConversationSession(from: proto)
    }
    
    public func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession] {
        let list = try await client.fetchAllSessions(MonadEmpty())
        let sessions = list.sessions.map { ConversationSession(from: $0) }
        if includeArchived {
            return sessions
        } else {
            return sessions.filter { !$0.isArchived }
        }
    }
    
    public func deleteSession(id: UUID) async throws {
        var request = MonadDeleteSessionRequest()
        request.id = id.uuidString
        _ = try await client.deleteSession(request)
    }
    
    public func searchArchivedSessions(query: String) async throws -> [ConversationSession] {
        // TODO: Add search support to gRPC if needed, or filter locally
        let all = try await fetchAllSessions(includeArchived: true)
        return all.filter { $0.isArchived && ($0.title.contains(query) || $0.tags.contains(query)) }
    }
    
    public func searchArchivedSessions(matchingAnyTag tags: [String]) async throws -> [ConversationSession] {
        let all = try await fetchAllSessions(includeArchived: true)
        return all.filter { session in
            session.isArchived && !Set(session.tagArray).intersection(tags).isEmpty
        }
    }
    
    // MARK: - Notes
    
    public func saveNote(_ note: Note) async throws {
        _ = try await noteClient.saveNote(note.toProto())
    }
    
    public func fetchNote(id: UUID) async throws -> Note? {
        // TODO: Add fetchNote to proto if needed
        let all = try await fetchAllNotes()
        return all.first { $0.id == id }
    }
    
    public func fetchAllNotes() async throws -> [Note] {
        let list = try await noteClient.fetchAllNotes(MonadEmpty())
        return list.notes.map { Note(from: $0) }
    }
    
    public func searchNotes(query: String) async throws -> [Note] {
        let all = try await fetchAllNotes()
        return all.filter { $0.matches(query: query) }
    }
    
    public func searchNotes(matchingAnyTag tags: [String]) async throws -> [Note] {
        let all = try await fetchAllNotes()
        return all.filter { note in
            !Set(note.tagArray).intersection(tags).isEmpty
        }
    }
    
    public func deleteNote(id: UUID) async throws {
        var request = MonadDeleteNoteRequest()
        request.id = id.uuidString
        _ = try await noteClient.deleteNote(request)
    }
    
    // MARK: - Memories
    
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID {
        let proto = try await memoryClient.saveMemory(memory.toProto())
        return UUID(uuidString: proto.id) ?? memory.id
    }
    
    public func fetchMemory(id: UUID) async throws -> Memory? {
        // TODO: Add fetchMemory to proto if needed
        let all = try await fetchAllMemories()
        return all.first { $0.id == id }
    }
    
    public func fetchAllMemories() async throws -> [Memory] {
        let list = try await memoryClient.fetchAllMemories(MonadEmpty())
        return list.memories.map { Memory(from: $0) }
    }
    
    public func searchMemories(query: String) async throws -> [Memory] {
        var request = MonadSearchRequest()
        request.text = query
        let response = try await memoryClient.searchMemories(request)
        return response.results.map { Memory(from: $0.memory) }
    }
    
    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)] {
        var request = MonadSearchRequest()
        var vecQuery = MonadEmbeddingQuery()
        vecQuery.vector = embedding
        vecQuery.minSimilarity = minSimilarity
        request.vector = vecQuery
        request.limit = Int32(limit)
        
        let response = try await memoryClient.searchMemories(request)
        return response.results.map { (Memory(from: $0.memory), $0.similarity) }
    }
    
    public func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] {
        let all = try await fetchAllMemories()
        return all.filter { mem in
            !Set(mem.tagArray).intersection(tags).isEmpty
        }
    }
    
    public func deleteMemory(id: UUID) async throws {
        var request = MonadDeleteMemoryRequest()
        request.id = id.uuidString
        _ = try await memoryClient.deleteMemory(request)
    }
    
    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws {
        if var memory = try await fetchMemory(id: id) {
            memory.embedding = String(data: try JSONEncoder().encode(newEmbedding), encoding: .utf8) ?? "[]"
            _ = try await saveMemory(memory, policy: .always)
        }
    }
    
    public func vacuumMemories(threshold: Double) async throws -> Int {
        // TODO: Support vacuum on server
        return 0
    }
    
    // MARK: - Messages
    
    public func saveMessage(_ message: ConversationMessage) async throws {
        // TODO: Support direct message saving if needed, or use Chat service
    }
    
    public func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] {
        // TODO: In server-side model, messages are usually fetched as part of ChatHistory
        return []
    }
    
    public func deleteMessages(for sessionId: UUID) async throws {
        // Handled by deleteSession on server
    }
    
    // MARK: - Jobs
    
    public func saveJob(_ job: Job) async throws {
        _ = try await jobClient.saveJob(job.toProto())
    }
    
    public func fetchJob(id: UUID) async throws -> Job? {
        let all = try await fetchAllJobs()
        return all.first { $0.id == id }
    }
    
    public func fetchAllJobs() async throws -> [Job] {
        let list = try await jobClient.fetchAllJobs(MonadEmpty())
        return list.jobs.map { Job(from: $0) }
    }
    
    public func deleteJob(id: UUID) async throws {
        var request = MonadDeleteJobRequest()
        request.id = id.uuidString
        _ = try await jobClient.deleteJob(request)
    }
    
    // MARK: - Table Directory
    
    public func fetchTableDirectory() async throws -> [TableDirectoryEntry] {
        // TODO: Add to gRPC if server-side SQL tools are used by client
        return []
    }
    
    // MARK: - RAW SQL Support
    
    public func executeRaw(sql: String, arguments: [DatabaseValue]) async throws -> [[String: AnyCodable]] {
        // TODO: Support proxying SQL to server
        return []
    }
    
    // MARK: - Database Management
    
    public func resetDatabase() async throws {
        // Not exposed via gRPC for safety
    }
}

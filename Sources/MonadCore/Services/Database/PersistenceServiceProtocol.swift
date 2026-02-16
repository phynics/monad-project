import MonadShared
import Foundation
import GRDB

/// Protocol for Persistence Service to enable mocking and isolation
public protocol PersistenceServiceProtocol: HealthCheckable {
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
    func fetchJobs(for sessionId: UUID) async throws -> [Job]
    func fetchPendingJobs(limit: Int) async throws -> [Job]
    func deleteJob(id: UUID) async throws
    func monitorJobs() async -> AsyncStream<JobEvent>

    // Database Management
    func resetDatabase() async throws
}

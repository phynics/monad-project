import Foundation
import GRDB


public final class MockPersistenceService: PersistenceServiceProtocol, @unchecked Sendable {
    public var databaseWriter: DatabaseWriter
    public var memories: [Memory] = []
    public var searchResults: [(memory: Memory, similarity: Double)] = []
    public var messages: [ConversationMessage] = []
    public var sessions: [ConversationSession] = []
    public var jobs: [Job] = []

    public init(databaseWriter: DatabaseWriter? = nil) {
        if let writer = databaseWriter {
            self.databaseWriter = writer
        } else {
            let queue = try! DatabaseQueue()
            var migrator = DatabaseMigrator()
            // Ensure we are using the correct schema from MonadCore
            DatabaseSchema.registerMigrations(in: &migrator)
            do {
                try migrator.migrate(queue)
                // Verify workspace table exists
                try queue.read { db in
                    if try !db.tableExists("workspace") {
                        fatalError("Migration failed: workspace table missing")
                    }
                }
            } catch {
                fatalError("Migration failed: \(error)")
            }
            self.databaseWriter = queue
        }
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

    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(
        memory: Memory, similarity: Double
    )] {
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

    public func updateMemory(_ memory: Memory) async throws {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        }
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

    public func pruneSessions(olderThan timeInterval: TimeInterval, excluding: [UUID] = []) async throws
        -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        let countBefore = sessions.count
        sessions.removeAll { session in
            !session.isArchived && session.updatedAt < cutoffDate && !excluding.contains(session.id)
        }
        return countBefore - sessions.count
    }

    public func pruneMessages(olderThan timeInterval: TimeInterval) async throws -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        let countBefore = messages.count
        messages.removeAll { $0.timestamp < cutoffDate }
        return countBefore - messages.count
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

    public func fetchJobs(for sessionId: UUID) async throws -> [Job] {
        return jobs.filter { $0.sessionId == sessionId }
    }

    public func deleteJob(id: UUID) async throws {
        jobs.removeAll(where: { $0.id == id })
    }

    // MARK: - Prune
    public func pruneMemories(matching query: String, dryRun: Bool) async throws -> Int {
        if dryRun {
            return memories.filter { $0.title.contains(query) || $0.content.contains(query) }.count
        }
        let countBefore = memories.count
        memories.removeAll { $0.title.contains(query) || $0.content.contains(query) }
        return countBefore - memories.count
    }

    public func pruneSessions(
        olderThan timeInterval: TimeInterval, excluding: [UUID] = [], dryRun: Bool
    ) async throws -> Int {
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

    public func pruneMessages(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        if dryRun {
            return messages.filter { $0.timestamp < cutoffDate }.count
        }
        let countBefore = messages.count
        messages.removeAll { $0.timestamp < cutoffDate }
        return countBefore - messages.count
    }

    // RAW SQL Support
    public func executeRaw(sql: String, arguments: [DatabaseValue]) async throws -> [[String: AnyCodable]] {
        // Simple mock implementation: return an error if it looks like a deletion we should block
        if sql.lowercased().contains("delete from note") {
            throw NSError(
                domain: "SQLite", code: 19,
                userInfo: [NSLocalizedDescriptionKey: "Notes cannot be deleted"])
        }
        return []
    }

    // Database Management
    public func resetDatabase() async throws {
        memories.removeAll()
        messages.removeAll()
        sessions.removeAll()
        jobs.removeAll()
    }
}

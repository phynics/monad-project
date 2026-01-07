import Foundation
import GRDB
import OSLog

/// Thread-safe persistence service using GRDB
/// Thread-safe persistence service using GRDB
public actor PersistenceService {
    private let dbQueue: DatabaseQueue
    private let logger = Logger.database

    // MARK: - Initialization

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public static func create(path: String? = nil) throws -> PersistenceService {
        let databasePath = path ?? Self.defaultDatabasePath()
        let queue = try DatabaseQueue(path: databasePath)
        try Self.performMigration(on: queue)
        return PersistenceService(dbQueue: queue)
    }

    /// Default database path in Application Support
    private static func defaultDatabasePath() -> String {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let appDir = appSupport.appendingPathComponent("MonadAssistant", isDirectory: true)

        try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)

        return appDir.appendingPathComponent("monad.sqlite").path
    }

    // MARK: - Migrations

    private static func performMigration(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        // Register all schema migrations
        DatabaseSchema.registerMigrations(in: &migrator)

        // Apply migrations
        try migrator.migrate(dbQueue)
    }

    // MARK: - Conversation Sessions

    public func saveSession(_ session: ConversationSession) throws {
        logger.debug("Saving session: \(session.id)")
        try dbQueue.write { db in
            try session.save(db)
        }
    }

    public func fetchSession(id: UUID) throws -> ConversationSession? {
        try dbQueue.read { db in
            try ConversationSession.fetchOne(db, key: ["id": id])
        }
    }

    public func fetchAllSessions(includeArchived: Bool = false) throws -> [ConversationSession] {
        try dbQueue.read { db in
            if includeArchived {
                return
                    try ConversationSession
                    .order(Column("updatedAt").desc)
                    .fetchAll(db)
            } else {
                return
                    try ConversationSession
                    .filter(Column("isArchived") == false)
                    .order(Column("updatedAt").desc)
                    .fetchAll(db)
            }
        }
    }

    public func deleteSession(id: UUID) throws {
        _ = try dbQueue.write { db in
            try ConversationSession.deleteOne(db, key: ["id": id])
        }
    }

    // MARK: - Messages

    public func saveMessage(_ message: ConversationMessage) throws {
        logger.debug("Saving message for session: \(message.sessionId)")
        try dbQueue.write { db in
            try message.save(db)
        }
    }

    public func fetchMessages(for sessionId: UUID) throws -> [ConversationMessage] {
        try dbQueue.read { db in
            try ConversationMessage
                .filter(Column("sessionId") == sessionId)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    // MARK: - Memories

    public func saveMemory(_ memory: Memory) throws {
        logger.debug("Saving memory: \(memory.title)")
        try dbQueue.write { db in
            try memory.save(db)
        }
    }

    public func fetchMemory(id: UUID) throws -> Memory? {
        try dbQueue.read { db in
            try Memory.fetchOne(db, key: ["id": id])
        }
    }

    public func fetchAllMemories() throws -> [Memory] {
        try dbQueue.read { db in
            try Memory
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    public func searchMemories(query: String) throws -> [Memory] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            return
                try Memory
                .filter(
                    Column("title").like(pattern) || Column("content").like(pattern)
                        || Column("tags").like(pattern)
                )
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }
    
    /// Search for memories that contain any of the provided tags
    public func searchMemories(matchingAnyTag tags: [String]) throws -> [Memory] {
        guard !tags.isEmpty else { return [] }
        
        return try dbQueue.read { db in
            // Basic approximation using LIKE. 
            // Ideally we would use FTS or JSON operators if available.
            // We construct a query that checks if the 'tags' column contains any of the target tags.
            // Since tags are stored as ["tag1","tag2"], searching for "%tag1%" is decent.
            
            var conditions: [SQLExpression] = []
            for tag in tags {
                conditions.append(Column("tags").like("%\(tag)%"))
            }
            
            let query = conditions.joined(operator: .or)
            
            let candidates = try Memory
                .filter(query)
                .fetchAll(db)
            
            // Post-filter to ensure strict tag matching (avoid substring matches like 'cat' matching 'catch')
            // This is safer.
            return candidates.filter { memory in
                let memoryTags = Set(memory.tagArray.map { $0.lowercased() })
                // Check intersection
                return !memoryTags.intersection(tags.map { $0.lowercased() }).isEmpty
            }
        }
    }

    /// Perform semantic search for memories
    /// - Parameters:
    ///   - embedding: The target vector to compare against
    ///   - limit: Maximum number of results
    ///   - minSimilarity: Minimum cosine similarity threshold (0.0 to 1.0)
    /// - Returns: Ranked memories with their similarity scores
    public func searchMemories(
        embedding: [Double],
        limit: Int = 5,
        minSimilarity: Double = 0.4
    ) throws -> [(memory: Memory, similarity: Double)] {
        // Fetch all memories with embeddings
        let allMemories = try fetchAllMemories()
        
        var results: [(memory: Memory, similarity: Double)] = []
        
        for memory in allMemories {
            let memoryVector = memory.embeddingVector
            guard !memoryVector.isEmpty else { continue }
            
            let similarity = cosineSimilarity(embedding, memoryVector)
            // logger.debug("Semantic similarity for '\(memory.title)': \(similarity)")
            if similarity >= minSimilarity {
                results.append((memory: memory, similarity: similarity))
            }
        }
        
        // Sort by similarity descending
        results.sort { $0.similarity > $1.similarity }
        
        return Array(results.prefix(limit))
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        
        var dotProduct = 0.0
        var magA = 0.0
        var magB = 0.0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        
        magA = sqrt(magA)
        magB = sqrt(magB)
        
        guard magA > 0 && magB > 0 else { return 0.0 }
        
        return dotProduct / (magA * magB)
    }

    public func deleteMemory(id: UUID) throws {
        _ = try dbQueue.write { db in
            try Memory.deleteOne(db, key: ["id": id])
        }
    }

    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) throws {
        try dbQueue.write { db in
            guard var memory = try Memory.fetchOne(db, key: ["id": id]) else { return }
            
            // Re-encode embedding array
            if let data = try? JSONEncoder().encode(newEmbedding), 
               let str = String(data: data, encoding: .utf8) {
                memory.embedding = str
                memory.updatedAt = Date()
                try memory.save(db)
            }
        }
    }

    // MARK: - Notes

    /// Save a note (create or update)
    public func saveNote(_ note: Note) throws {
        logger.debug("Saving note: \(note.name)")
        try dbQueue.write { db in
            try note.save(db)
        }
    }

    /// Fetch a single note by ID
    public func fetchNote(id: UUID) throws -> Note? {
        try dbQueue.read { db in
            try Note.fetchOne(db, key: ["id": id])
        }
    }

    /// Fetch all notes ordered by name
    public func fetchAllNotes() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Fetch notes that should always be appended to context
    public func fetchAlwaysAppendNotes() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Column("alwaysAppend") == true)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Search notes by query (matches name, description, or content)
    public func searchNotes(query: String) throws -> [Note] {
        guard !query.isEmpty else {
            return try fetchAllNotes()
        }

        return try dbQueue.read { db in
            let pattern = "%\(query)%"
            return
                try Note
                .filter(
                    Column("name").like(pattern) || Column("description").like(pattern)
                        || Column("content").like(pattern)
                )
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Delete a note (only if not readonly)
    public func deleteNote(id: UUID) throws {
        try dbQueue.write { db in
            // Check if note is readonly
            if let note = try Note.fetchOne(db, key: ["id": id]), note.isReadonly {
                throw NoteError.noteIsReadonly
            }
            try Note.deleteOne(db, key: ["id": id])
        }
    }

    /// Get all notes formatted for context injection
    public func getContextNotes(alwaysAppend: Bool = false) throws -> String {
        let notes = alwaysAppend ? try fetchAlwaysAppendNotes() : try fetchAllNotes()
        guard !notes.isEmpty else { return "" }

        return notes.map { note in
            """
            ### \(note.name)
            \(note.content)
            """
        }.joined(separator: "\n\n")
    }

    // MARK: - Search Archived Sessions

    public func searchArchivedSessions(query: String) throws -> [ConversationSession] {
        try dbQueue.read { db in
            let pattern = "%\(query)%"
            return
                try ConversationSession
                .filter(Column("isArchived") == true)
                .filter(Column("title").like(pattern) || Column("tags").like(pattern))
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    // MARK: - Database Reset

    /// Reset the entire database (deletes all data)
    public func resetDatabase() throws {
        try dbQueue.write { db in
            // Delete all data from all tables
            try ConversationMessage.deleteAll(db)
            try ConversationSession.deleteAll(db)
            try Memory.deleteAll(db)
            try Note.deleteAll(db)

            // Recreate default notes
            try DatabaseSchema.createDefaultNotes(in: db)
        }
    }
}

// MARK: - Errors

public enum NoteError: LocalizedError {
    case noteIsReadonly

    public var errorDescription: String? {
        switch self {
        case .noteIsReadonly:
            return "Cannot delete readonly note"
        }
    }
}

// UUID support is already provided by GRDB

import Foundation
import GRDB

/// Thread-safe persistence service using GRDB
actor PersistenceService {
    private let dbQueue: DatabaseQueue

    // MARK: - Initialization

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    static func create(path: String? = nil) throws -> PersistenceService {
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

    func saveSession(_ session: ConversationSession) throws {
        try dbQueue.write { db in
            try session.save(db)
        }
    }

    func fetchSession(id: UUID) throws -> ConversationSession? {
        try dbQueue.read { db in
            try ConversationSession.fetchOne(db, key: ["id": id])
        }
    }

    func fetchAllSessions(includeArchived: Bool = false) throws -> [ConversationSession] {
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

    func deleteSession(id: UUID) throws {
        _ = try dbQueue.write { db in
            try ConversationSession.deleteOne(db, key: ["id": id])
        }
    }

    // MARK: - Messages

    func saveMessage(_ message: ConversationMessage) throws {
        try dbQueue.write { db in
            try message.save(db)
        }
    }

    func fetchMessages(for sessionId: UUID) throws -> [ConversationMessage] {
        try dbQueue.read { db in
            try ConversationMessage
                .filter(Column("sessionId") == sessionId)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    // MARK: - Memories

    func saveMemory(_ memory: Memory) throws {
        try dbQueue.write { db in
            try memory.save(db)
        }
    }

    func fetchMemory(id: UUID) throws -> Memory? {
        try dbQueue.read { db in
            try Memory.fetchOne(db, key: ["id": id])
        }
    }

    func fetchAllMemories() throws -> [Memory] {
        try dbQueue.read { db in
            try Memory
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    func searchMemories(query: String) throws -> [Memory] {
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

    func deleteMemory(id: UUID) throws {
        _ = try dbQueue.write { db in
            try Memory.deleteOne(db, key: ["id": id])
        }
    }

    // MARK: - Notes

    /// Save a note (create or update)
    func saveNote(_ note: Note) throws {
        try dbQueue.write { db in
            try note.save(db)
        }
    }

    /// Fetch a single note by ID
    func fetchNote(id: UUID) throws -> Note? {
        try dbQueue.read { db in
            try Note.fetchOne(db, key: ["id": id])
        }
    }

    /// Fetch all notes ordered by name
    func fetchAllNotes() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Fetch notes that should always be appended to context
    func fetchAlwaysAppendNotes() throws -> [Note] {
        try dbQueue.read { db in
            try Note
                .filter(Column("alwaysAppend") == true)
                .order(Column("name").asc)
                .fetchAll(db)
        }
    }

    /// Search notes by query (matches name, description, or content)
    func searchNotes(query: String) throws -> [Note] {
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
    func deleteNote(id: UUID) throws {
        try dbQueue.write { db in
            // Check if note is readonly
            if let note = try Note.fetchOne(db, key: ["id": id]), note.isReadonly {
                throw NoteError.noteIsReadonly
            }
            try Note.deleteOne(db, key: ["id": id])
        }
    }

    /// Get all notes formatted for context injection
    func getContextNotes(alwaysAppend: Bool = false) throws -> String {
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

    func searchArchivedSessions(query: String) throws -> [ConversationSession] {
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
    func resetDatabase() throws {
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

enum NoteError: LocalizedError {
    case noteIsReadonly

    var errorDescription: String? {
        switch self {
        case .noteIsReadonly:
            return "Cannot delete readonly note"
        }
    }
}

// UUID support is already provided by GRDB

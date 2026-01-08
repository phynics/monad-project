import Foundation
import GRDB

/// Database schema definitions and migrations
public enum DatabaseSchema {

    /// Register all migrations
    public static func registerMigrations(in migrator: inout DatabaseMigrator) {
        // v1: Baseline schema (consolidated v1 and v2)
        migrator.registerMigration("v1") { db in
            try createConversationTables(in: db)
            try createMemoryTable(in: db)
            try createNoteTable(in: db)
            try createDefaultNotes(in: db)
        }
        
        // v2: Add embedding to Memory
        migrator.registerMigration("v2") { db in
            if try !db.columns(in: "memory").contains(where: { $0.name == "embedding" }) {
                try db.alter(table: "memory") { t in
                    t.add(column: "embedding", .text).notNull().defaults(to: "[]")
                }
            }
        }
        
        // v3: Retry adding embedding column if missing (for dev state consistency)
        migrator.registerMigration("v3") { db in
            if try !db.columns(in: "memory").contains(where: { $0.name == "embedding" }) {
                try db.alter(table: "memory") { t in
                    t.add(column: "embedding", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v4: Add recalledMemories to conversationMessage
        migrator.registerMigration("v4") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "recalledMemories" }) {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "recalledMemories", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v5: Add memoryId to conversationMessage
        migrator.registerMigration("v5") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "memoryId" }) {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "memoryId", .blob).references("memory", onDelete: .setNull)
                }
            }
        }

        // v6: Add tags to Note
        migrator.registerMigration("v6") { db in
            if try !db.columns(in: "note").contains(where: { $0.name == "tags" }) {
                try db.alter(table: "note") { t in
                    t.add(column: "tags", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v7: Convert conversationSession tags from base64 to JSON
        migrator.registerMigration("v7") { db in
            let sessions = try ConversationSession.fetchAll(db)
            for var session in sessions {
                // Try to detect if it's base64 encoded. 
                // A simple JSON array string like '["a"]' is not valid base64 usually,
                // but a base64 string won't start with '['.
                if !session.tags.isEmpty && !session.tags.hasPrefix("[") {
                    if let data = Data(base64Encoded: session.tags),
                       let tagsArray = try? JSONDecoder().decode([String].self, from: data),
                       let newData = try? JSONEncoder().encode(tagsArray),
                       let newString = String(data: newData, encoding: .utf8) {
                        session.tags = newString
                        try session.update(db)
                    }
                }
            }
        }

        // v8: Add parentId to conversationMessage for tree structure
        migrator.registerMigration("v8") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "parentId" }) {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "parentId", .blob).references("conversationMessage", onDelete: .setNull)
                }
            }
        }
    }

    // MARK: - Conversation Tables

    private static func createConversationTables(in db: Database) throws {
        // Conversation sessions
        try db.create(table: "conversationSession") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("title", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("isArchived", .boolean).notNull().defaults(to: false)
            t.column("tags", .text).notNull().defaults(to: "")
        }

        // Conversation messages
        try db.create(table: "conversationMessage") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("sessionId", .blob).notNull()
                .references("conversationSession", onDelete: .cascade)
            t.column("role", .text).notNull()
            t.column("content", .text).notNull()
            t.column("timestamp", .datetime).notNull()
        }

        // Indexes for conversations
        try db.create(
            index: "idx_message_session",
            on: "conversationMessage",
            columns: ["sessionId"])
        try db.create(
            index: "idx_message_timestamp",
            on: "conversationMessage",
            columns: ["timestamp"])
    }

    // MARK: - Memory Table

    private static func createMemoryTable(in db: Database) throws {
        try db.create(table: "memory") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("title", .text).notNull()
            t.column("content", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("tags", .text).notNull().defaults(to: "")
            t.column("metadata", .text).notNull().defaults(to: "")
            t.column("embedding", .text).notNull().defaults(to: "[]")
        }
    }

    // MARK: - Note Table

    private static func createNoteTable(in db: Database) throws {
        try db.create(table: "note") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("name", .text).notNull()
            t.column("description", .text).notNull().defaults(to: "")
            t.column("content", .text).notNull()
            t.column("isReadonly", .boolean).notNull().defaults(to: false)
            t.column("alwaysAppend", .boolean).notNull().defaults(to: false)
            t.column("tags", .text).notNull().defaults(to: "[]")
            t.column("isEnabled", .boolean).notNull().defaults(to: true)
            t.column("priority", .integer).notNull().defaults(to: 0)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        // Indexes for notes
        try db.create(
            index: "idx_note_alwaysAppend",
            on: "note",
            columns: ["alwaysAppend"])
        try db.create(
            index: "idx_note_readonly",
            on: "note",
            columns: ["isReadonly"])
    }

    // MARK: - Default Notes

    /// Create default context notes
    public static func createDefaultNotes(in db: Database) throws {
        let now = Date()

        // System Note (Readonly, Always Append)
        let systemNote = Note(
            name: "System",
            description: "Core capabilities and operational constraints.",
            content: """
                Operational Rules:
                - Use tools only when necessary for information retrieval or state updates.
                - DO NOT use tools for greetings or general conversation.
                - Persona: technical, professional, and concise. No emojis.
                - Prioritize context notes and memories for accuracy and personalization.
                """,
            isReadonly: true,
            alwaysAppend: true,
            createdAt: now,
            updatedAt: now
        )
        try systemNote.insert(db)

        // Persona Note (Editable, Always Append)
        let personaNote = Note(
            name: "Persona",
            description: "AI personality and behavioral guidelines.",
            content: """
                Guidelines for AI personality, communication style, and behavioral preferences.
                [EMPTY; FILL AS NEEDED]
                """,
            isReadonly: false,
            alwaysAppend: true,
            createdAt: now,
            updatedAt: now
        )
        try personaNote.insert(db)

        // Human Note (Editable, Always Append)
        let humanNote = Note(
            name: "Human",
            description: "Information about the user.",
            content: """
                Information about the user, their preferences, and current focus.
                [EMPTY; FILL AS NEEDED]
                """,
            isReadonly: false,
            alwaysAppend: true,
            createdAt: now,
            updatedAt: now
        )
        try humanNote.insert(db)

        // Scratchpad Note (Editable, Always Append)
        let scratchpadNote = Note(
            name: "Scratchpad",
            description: "Temporary storage for planning.",
            content: """
                Temporary storage for Todo lists, planning, and short-term state tracking.
                [EMPTY; FILL AS NEEDED]
                """,
            alwaysAppend: true
        )
        try scratchpadNote.insert(db)
    }
}

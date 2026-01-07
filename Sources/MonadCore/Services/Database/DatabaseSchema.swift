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
            description: "Core system instructions and capabilities",
            content: """
                You are an AI assistant with access to the user's context. You have:
                - Access to conversation history
                - Context notes for project-specific information
                - Ability to learn and adapt based on user preferences

                Always be helpful, accurate, and concise. Use the provided context to give relevant responses.
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
            description: "AI personality and behavioral guidelines",
            content: """
                ## Communication Style
                - Be clear and direct
                - Use technical language when appropriate
                - Provide examples when helpful

                ## Approach
                - Ask clarifying questions when needed
                - Break down complex problems
                - Suggest best practices
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
            description: "Information about the user",
            content: """
                ## User Information
                [Add information about user here]

                ## Preferences
                [Add user's preferences here]

                ## Current Projects
                [Add information about what user is working on]
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
            description: "A Todo list, note-to-self, short term planing, etc.",
            content: """
                Let's take things step by step:
                - [ ] Make a plan
                - [ ] Put the plan in the scratchpad
                - [ ] Profit!
                """,
            alwaysAppend: true
        )
        try scratchpadNote.insert(db)
    }
}

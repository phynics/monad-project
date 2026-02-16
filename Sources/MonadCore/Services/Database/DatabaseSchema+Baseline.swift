import Foundation
import GRDB

extension DatabaseSchema {
    // MARK: - Workspace Tables

    internal static func createWorkspaceTables(in db: Database) throws {
        // Client entity table
        try db.create(table: "clientIdentity") { t in
            t.column("id", .blob).primaryKey()
            t.column("hostname", .text).notNull()
            t.column("displayName", .text).notNull()
            t.column("platform", .text).notNull()
            t.column("registeredAt", .datetime).notNull()
            t.column("lastSeenAt", .datetime)
        }

        // Workspace table
        try db.create(table: "workspace") { t in
            t.column("id", .blob).primaryKey()
            t.column("uri", .text).notNull().unique()
            t.column("hostType", .text).notNull()
            t.column("ownerId", .blob).references("clientIdentity", onDelete: .setNull)
            t.column("rootPath", .text)
            t.column("trustLevel", .text).notNull().defaults(to: "full")
            t.column("lastModifiedBy", .blob)
            t.column("status", .text).notNull().defaults(to: "active")
            t.column("createdAt", .datetime).notNull()
        }

        // Workspace tools (tool definitions per workspace)
        try db.create(table: "workspaceTool") { t in
            t.column("id", .blob).primaryKey()
            t.column("workspaceId", .blob).notNull()
                .references("workspace", onDelete: .cascade)
            t.column("toolId", .text).notNull()
            t.column("isKnown", .boolean).notNull()
            t.column("definition", .text)
        }
        try db.create(
            index: "idx_workspaceTool_workspace",
            on: "workspaceTool",
            columns: ["workspaceId"])

        // Workspace locks
        try db.create(table: "workspaceLock") { t in
            t.column("workspaceId", .blob).primaryKey()
                .references("workspace", onDelete: .cascade)
            t.column("heldBy", .blob).notNull()
            t.column("acquiredAt", .datetime).notNull()
        }
    }

    // MARK: - Conversation Tables

    internal static func createConversationTables(in db: Database) throws {
        // Conversation sessions
        try db.create(table: "conversationSession") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("title", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("isArchived", .boolean).notNull().defaults(to: false)
            t.column("tags", .text).notNull().defaults(to: "")
            t.column("workingDirectory", .text)
            t.column("primaryWorkspaceId", .blob)
            t.column("attachedWorkspaceIds", .text).notNull().defaults(to: "[]")
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

    internal static func createMemoryTable(in db: Database) throws {
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

    internal static func createNoteTable(in db: Database) throws {
        try db.create(table: "note") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("name", .text).notNull()
            t.column("description", .text).notNull().defaults(to: "")
            t.column("content", .text).notNull()
            t.column("isReadonly", .boolean).notNull().defaults(to: false)
            t.column("tags", .text).notNull().defaults(to: "[]")
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }

        // Indexes for notes
        try db.create(
            index: "idx_note_readonly",
            on: "note",
            columns: ["isReadonly"])
    }

    // MARK: - Default Notes

    /// Create default context notes
    internal static func createDefaultNotes(in db: Database) throws {
        let now = Date()

        // System Note (Readonly)
        let systemNote = Note(
            name: "System",
            description: "Core capabilities and operational constraints.",
            content: """
                Operational Rules:
                - Use SQL via `execute_sql` for data retrieval and state management.
                - Self-Documenting Schema: Use `table_directory` to explore existing tables and document your own.
                - All context notes in the `note` table are injected globally into your system prompt.
                - Archives (History) and Notes are protected. Deletion is blocked.
                """,
            isReadonly: true,
            createdAt: now,
            updatedAt: now
        )
        try systemNote.insert(db)


        // Human Note (Editable)
        let humanNote = Note(
            name: "Human",
            description: "Information about the user.",
            content: """
                Information about the user, their preferences, and current focus.
                [EMPTY; FILL AS NEEDED]
                """,
            isReadonly: false,
            createdAt: now,
            updatedAt: now
        )
        try humanNote.insert(db)

        // Scratchpad Note (Editable)
        let scratchpadNote = Note(
            name: "Scratchpad",
            description: "Temporary storage for planning.",
            content: """
                Temporary storage for Todo lists, planning, and short-term state tracking.
                [EMPTY; FILL AS NEEDED]
                """
        )
        try scratchpadNote.insert(db)
    }
}

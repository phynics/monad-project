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
            if try !db.columns(in: "conversationMessage").contains(where: {
                $0.name == "recalledMemories"
            }) {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "recalledMemories", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v5: Add memoryId to conversationMessage
        migrator.registerMigration("v5") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "memoryId" })
            {
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
                        let newString = String(data: newData, encoding: .utf8)
                    {
                        session.tags = newString
                        try session.update(db)
                    }
                }
            }
        }

        // v8: Add parentId to conversationMessage for tree structure
        migrator.registerMigration("v8") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "parentId" })
            {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "parentId", .blob).references(
                        "conversationMessage", onDelete: .setNull)
                }
            }
        }

        // v9: Add think and toolCalls to conversationMessage
        migrator.registerMigration("v9") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "think" }) {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "think", .text)
                }
            }
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "toolCalls" }
            ) {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "toolCalls", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v10: Add workingDirectory to conversationSession
        migrator.registerMigration("v10") { db in
            if try !db.columns(in: "conversationSession").contains(where: {
                $0.name == "workingDirectory"
            }) {
                try db.alter(table: "conversationSession") { t in
                    t.add(column: "workingDirectory", .text)
                }
            }
        }

        // v11: Add triggers for immutability
        migrator.registerMigration("v11") { db in
            // Protect Notes from deletion
            try db.execute(
                sql: """
                        CREATE TRIGGER IF NOT EXISTS prevent_note_deletion
                        BEFORE DELETE ON note
                        BEGIN
                            SELECT RAISE(ABORT, 'Notes cannot be deleted');
                        END;
                    """)

            // Protect Archives (Sessions and Messages) from deletion and modification
            try db.execute(
                sql: """
                        CREATE TRIGGER IF NOT EXISTS prevent_session_deletion
                        BEFORE DELETE ON conversationSession
                        FOR EACH ROW
                        WHEN OLD.isArchived = 1
                        BEGIN
                            SELECT RAISE(ABORT, 'Archived sessions cannot be deleted');
                        END;
                    """)

            try db.execute(
                sql: """
                        CREATE TRIGGER IF NOT EXISTS prevent_session_modification
                        BEFORE UPDATE ON conversationSession
                        FOR EACH ROW
                        WHEN OLD.isArchived = 1
                        BEGIN
                            SELECT RAISE(ABORT, 'Archived sessions cannot be modified');
                        END;
                    """)

            try db.execute(
                sql: """
                        CREATE TRIGGER IF NOT EXISTS prevent_message_deletion
                        BEFORE DELETE ON conversationMessage
                        FOR EACH ROW
                        WHEN (SELECT isArchived FROM conversationSession WHERE id = OLD.sessionId) = 1
                        BEGIN
                            SELECT RAISE(ABORT, 'Archived messages cannot be deleted');
                        END;
                    """)

            try db.execute(
                sql: """
                        CREATE TRIGGER IF NOT EXISTS prevent_message_modification
                        BEFORE UPDATE ON conversationMessage
                        FOR EACH ROW
                        WHEN (SELECT isArchived FROM conversationSession WHERE id = OLD.sessionId) = 1
                        BEGIN
                            SELECT RAISE(ABORT, 'Archived messages cannot be modified');
                        END;
                    """)
        }

        // v12: Remove alwaysAppend, isEnabled, and priority from Note
        migrator.registerMigration("v12") { db in
            try db.execute(sql: "DROP INDEX IF EXISTS idx_note_alwaysAppend")

            let columns = try db.columns(in: "note").map { $0.name }

            try db.alter(table: "note") { t in
                if columns.contains("alwaysAppend") {
                    t.drop(column: "alwaysAppend")
                }
                if columns.contains("isEnabled") {
                    t.drop(column: "isEnabled")
                }
                if columns.contains("priority") {
                    t.drop(column: "priority")
                }
            }
        }

        // v13: Add table_directory for self-documenting schema
        migrator.registerMigration("v13") { db in
            try db.create(table: "table_directory") { t in
                t.column("name", .text).primaryKey()
                t.column("description", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
            }
        }

        // v14: Add job table for persistent task queue
        migrator.registerMigration("v14") { db in
            try db.create(table: "job") { t in
                t.column("id", .blob).primaryKey()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
        }

        // v15: Add compactificationNode table for context compression
        migrator.registerMigration("v15") { db in
            try db.create(table: "compactificationNode") { t in
                t.column("id", .blob).primaryKey()
                t.column("sessionId", .blob).notNull()
                    .references("conversationSession", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("summary", .text).notNull()
                t.column("displayHint", .text).notNull()
                t.column("childIds", .text).notNull()
                t.column("metadata", .text).notNull().defaults(to: "{}")
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_compactificationNode_session",
                on: "compactificationNode",
                columns: ["sessionId"])
        }

        // v16: Workspaces and Client Identity
        migrator.registerMigration("v16") { db in
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
                t.column("lastModifiedBy", .blob).references(
                    "conversationSession", onDelete: .setNull)
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

            // Add workspace columns to session
            try db.alter(table: "conversationSession") { t in
                t.add(column: "primaryWorkspaceId", .blob)
                    .references("workspace", onDelete: .setNull)
                t.add(column: "attachedWorkspaceIds", .text).notNull().defaults(to: "[]")
            }

            // Workspace locks
            try db.create(table: "workspaceLock") { t in
                t.column("workspaceId", .blob).primaryKey()
                    .references("workspace", onDelete: .cascade)
                t.column("heldBy", .blob).notNull()
                    .references("conversationSession", onDelete: .cascade)
                t.column("acquiredAt", .datetime).notNull()
            }
        }

        // v17: Add toolCallId to conversationMessage (for 'tool' role messages)
        migrator.registerMigration("v17") { db in
            if try !db.columns(in: "conversationMessage").contains(where: {
                $0.name == "toolCallId"
            }) {
                try db.alter(table: "conversationMessage") { t in
                    t.add(column: "toolCallId", .text)
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
    public static func createDefaultNotes(in db: Database) throws {
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
                - Persona: technical, professional, and concise. No emojis.
                """,
            isReadonly: true,
            createdAt: now,
            updatedAt: now
        )
        try systemNote.insert(db)

        // Persona Note (Editable)
        let personaNote = Note(
            name: "Persona",
            description: "AI personality and behavioral guidelines.",
            content: """
                Guidelines for AI personality, communication style, and behavioral preferences.
                [EMPTY; FILL AS NEEDED]
                """,
            isReadonly: false,
            createdAt: now,
            updatedAt: now
        )
        try personaNote.insert(db)

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

import MonadShared
import Foundation
import GRDB

extension DatabaseSchema {
    /// Register all migrations
    public static func registerMigrations(in migrator: inout DatabaseMigrator) {
        // v1: Baseline schema (consolidated v1 and v2)
        migrator.registerMigration("v1") { db in
            try createWorkspaceTables(in: db)
            try createConversationTables(in: db)
            try createMemoryTable(in: db)
            // Note table removed
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

        // v6: Add tags to Note (Removed)
        migrator.registerMigration("v6") { db in
            // No-op
        }

        // v7: Convert conversationSession tags from base64 to JSON
        migrator.registerMigration("v7") { db in
            let sessions = try ConversationSession.fetchAll(db)
            for var session in sessions {
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
        // v11: Add triggers for immutability
        migrator.registerMigration("v11") { db in
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
        // v12: Remove alwaysAppend, isEnabled, and priority from Note (Removed)
        migrator.registerMigration("v12") { db in
           // No-op
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
            if try !db.tableExists("clientIdentity") {
                try createWorkspaceTables(in: db)
            }

            if try db.tableExists("conversationSession") {
                let columns = try db.columns(in: "conversationSession").map { $0.name }
                try db.alter(table: "conversationSession") { t in
                    if !columns.contains("primaryWorkspaceId") {
                        t.add(column: "primaryWorkspaceId", .blob)
                            .references("workspace", onDelete: .setNull)
                    }
                    if !columns.contains("attachedWorkspaceIds") {
                        t.add(column: "attachedWorkspaceIds", .text).notNull().defaults(to: "[]")
                    }
                }
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

        // v18: Remove legacy Note table
        migrator.registerMigration("v18") { db in
            // Note table removal logic removed
        }

        // v19: Restore Note table
        // v19: Restore Note table (Removed)
        migrator.registerMigration("v19") { db in
            // No-op
        }

        // v20: Add persona column to conversationSession
        migrator.registerMigration("v20") { db in
            if try !db.columns(in: "conversationSession").contains(where: { $0.name == "persona" })
            {
                try db.alter(table: "conversationSession") { t in
                    t.add(column: "persona", .text)
                }
            }
        }

        // v21: Fix protection triggers
        migrator.registerMigration("v21") { db in
            try db.execute(sql: "DROP TRIGGER IF EXISTS prevent_session_deletion")
            try db.execute(sql: "DROP TRIGGER IF EXISTS prevent_session_modification")
            try db.execute(sql: "DROP TRIGGER IF EXISTS prevent_message_deletion")
            try db.execute(sql: "DROP TRIGGER IF EXISTS prevent_message_modification")

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

        // v22: Add sessionId to Job table
        migrator.registerMigration("v22") { db in
            try db.drop(table: "job")

            try db.create(table: "job") { t in
                t.column("id", .blob).primaryKey()
                t.column("sessionId", .blob).notNull()
                    .references("conversationSession", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
            try db.create(index: "idx_job_session", on: "job", columns: ["sessionId"])
        }

        // v23: Add status to workspace table
        migrator.registerMigration("v23") { db in
            if try !db.columns(in: "workspace").contains(where: { $0.name == "status" }) {
                try db.alter(table: "workspace") { t in
                    t.add(column: "status", .text).notNull().defaults(to: "active")
                }
            }
        }

        // v24: Add agentId to Job table
        migrator.registerMigration("v24") { db in
            try db.drop(table: "job")

            try db.create(table: "job") { t in
                t.column("id", .blob).primaryKey()
                t.column("sessionId", .blob).notNull()
                    .references("conversationSession", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("agentId", .text).notNull().defaults(to: "default")
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
            try db.create(index: "idx_job_session", on: "job", columns: ["sessionId"])
            try db.create(index: "idx_job_agent", on: "job", columns: ["agentId"])
        }

        // v25: Add missing columns to Job table
        migrator.registerMigration("v25") { db in
            try db.drop(table: "job")

            try db.create(table: "job") { t in
                t.column("id", .blob).primaryKey()
                t.column("sessionId", .blob).notNull()
                    .references("conversationSession", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("agentId", .text).notNull().defaults(to: "default")
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("logs", .text).notNull().defaults(to: "[]")
                t.column("retryCount", .integer).notNull().defaults(to: 0)
                t.column("lastRetryAt", .datetime)
                t.column("nextRunAt", .datetime)
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
            try db.create(index: "idx_job_session", on: "job", columns: ["sessionId"])
            try db.create(index: "idx_job_agent", on: "job", columns: ["agentId"])
        }

        // v26: Add parentId to Job table for task trees
        migrator.registerMigration("v26") { db in
            if try !db.columns(in: "job").contains(where: { $0.name == "parentId" }) {
                try db.alter(table: "job") { t in
                    t.add(column: "parentId", .blob).references("job", onDelete: .cascade)
                }
            }
            try db.create(index: "idx_job_parent", on: "job", columns: ["parentId"])
        }

        // v27: Add agent table for simplified, data-driven agents
        migrator.registerMigration("v27") { db in
            try createAgentTable(in: db)

            // Seed with default agent
            let defaultAgent = Agent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Default Assistant",
                description: "A general purpose assistant focused on helpfulness and accuracy.",
                systemPrompt: """
                You are a helpful, intelligent, and efficient AI assistant named Monad.
                Your goal is to assist the user with their tasks while being concise and professional.
                """
            )
            try defaultAgent.insert(db)
            
            // Seed with coordinator agent
            let coordinatorAgent = Agent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "Agent Coordinator",
                description: "Coordinates multiple agents and complex workflows.",
                systemPrompt: """
                You are the Monad Coordinator. Your role is to break down complex tasks into smaller sub-tasks 
                and delegate them to specialized agents.
                """
            )
            try coordinatorAgent.insert(db)
        }
    }
}

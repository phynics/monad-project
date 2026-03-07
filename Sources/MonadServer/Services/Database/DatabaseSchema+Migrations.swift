import Foundation
import GRDB
import MonadCore
import MonadShared

public extension DatabaseSchema {
    /// Register all migrations
    static func registerMigrations(in migrator: inout DatabaseMigrator) {
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
                try db.alter(table: "memory") { table in
                    table.add(column: "embedding", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v3: Retry adding embedding column if missing (for dev state consistency)
        migrator.registerMigration("v3") { db in
            if try !db.columns(in: "memory").contains(where: { $0.name == "embedding" }) {
                try db.alter(table: "memory") { table in
                    table.add(column: "embedding", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v4: Add recalledMemories to conversationMessage
        migrator.registerMigration("v4") { db in
            if try !db.columns(in: "conversationMessage").contains(where: {
                $0.name == "recalledMemories"
            }) {
                try db.alter(table: "conversationMessage") { table in
                    table.add(column: "recalledMemories", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v5: Add memoryId to conversationMessage
        migrator.registerMigration("v5") { db in
            // Skip if v29 already removed it or if it somehow doesn't exist
            if try db.columns(in: "conversationMessage").contains(where: { $0.name == "memoryId" }) {
                // No-op, it already exists or will be added/removed later.
                // Actually, if we are at v5, we want to add it.
            } else {
                // If it's missing at this stage, it might be because baseline removed it.
                // But baseline should match the LATEST schema.
                // Migrations should handle the EVOLUTION.
                try db.alter(table: "conversationMessage") { table in
                    table.add(column: "memoryId", .blob).references("memory", onDelete: .setNull)
                }
            }
        }

        // v6: Add tags to Note (Removed)
        migrator.registerMigration("v6") { _ in
            // No-op
        }

        // v7: Convert timeline tags from base64 to JSON
        migrator.registerMigration("v7") { db in
            let timelines = try Timeline.fetchAll(db)
            for var timeline in timelines {
                if !timeline.tags.isEmpty, !timeline.tags.hasPrefix("[") {
                    if let data = Data(base64Encoded: timeline.tags),
                       let tagsArray = try? JSONDecoder().decode([String].self, from: data),
                       let newData = try? JSONEncoder().encode(tagsArray),
                       let newString = String(data: newData, encoding: .utf8)
                    {
                        timeline.tags = newString
                        try timeline.update(db)
                    }
                }
            }
        }

        // v8: Add parentId to conversationMessage for tree structure
        migrator.registerMigration("v8") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "parentId" }) {
                try db.alter(table: "conversationMessage") { table in
                    table.add(column: "parentId", .blob).references(
                        "conversationMessage", onDelete: .setNull
                    )
                }
            }
        }

        // v9: Add think and toolCalls to conversationMessage
        migrator.registerMigration("v9") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "think" }) {
                try db.alter(table: "conversationMessage") { table in
                    table.add(column: "think", .text)
                }
            }
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "toolCalls" }) {
                try db.alter(table: "conversationMessage") { table in
                    table.add(column: "toolCalls", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v10: Add workingDirectory to timeline
        migrator.registerMigration("v10") { db in
            if try !db.columns(in: "timeline").contains(where: {
                $0.name == "workingDirectory"
            }) {
                try db.alter(table: "timeline") { table in
                    table.add(column: "workingDirectory", .text)
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
                    BEFORE DELETE ON timeline
                    FOR EACH ROW
                    WHEN OLD.isArchived = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived timelines cannot be deleted');
                    END;
                """
            )

            try db.execute(
                sql: """
                    CREATE TRIGGER IF NOT EXISTS prevent_session_modification
                    BEFORE UPDATE ON timeline
                    FOR EACH ROW
                    WHEN OLD.isArchived = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived timelines cannot be modified');
                    END;
                """
            )

            try db.execute(
                sql: """
                    CREATE TRIGGER IF NOT EXISTS prevent_message_deletion
                    BEFORE DELETE ON conversationMessage
                    FOR EACH ROW
                    WHEN (SELECT isArchived FROM timeline WHERE id = OLD.timelineId) = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived messages cannot be deleted');
                    END;
                """
            )

            try db.execute(
                sql: """
                    CREATE TRIGGER IF NOT EXISTS prevent_message_modification
                    BEFORE UPDATE ON conversationMessage
                    FOR EACH ROW
                    WHEN (SELECT isArchived FROM timeline WHERE id = OLD.timelineId) = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived messages cannot be modified');
                    END;
                """
            )
        }

        // v12: Remove alwaysAppend, isEnabled, and priority from Note
        // v12: Remove alwaysAppend, isEnabled, and priority from Note (Removed)
        migrator.registerMigration("v12") { _ in
            // No-op
        }

        // v13: Add table_directory for self-documenting schema
        migrator.registerMigration("v13") { db in
            try db.create(table: "table_directory") { table in
                table.column("name", .text).primaryKey()
                table.column("description", .text).notNull().defaults(to: "")
                table.column("createdAt", .datetime).notNull()
            }
        }

        // v14: Add job table for persistent task queue
        migrator.registerMigration("v14") { db in
            try db.create(table: "job") { table in
                table.column("id", .blob).primaryKey()
                table.column("title", .text).notNull()
                table.column("description", .text)
                table.column("priority", .integer).notNull().defaults(to: 0)
                table.column("status", .text).notNull().defaults(to: "pending")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
        }

        // v15: Add compactificationNode table for context compression
        migrator.registerMigration("v15") { db in
            try db.create(table: "compactificationNode") { table in
                table.column("id", .blob).primaryKey()
                table.column("timelineId", .blob).notNull()
                    .references("timeline", onDelete: .cascade)
                table.column("type", .text).notNull()
                table.column("summary", .text).notNull()
                table.column("displayHint", .text).notNull()
                table.column("childIds", .text).notNull()
                table.column("metadata", .text).notNull().defaults(to: "{}")
                table.column("createdAt", .datetime).notNull()
            }

            try db.create(
                index: "idx_compactificationNode_session",
                on: "compactificationNode",
                columns: ["timelineId"]
            )
        }

        // v16: Workspaces and Client Identity
        migrator.registerMigration("v16") { db in
            if try !db.tableExists("clientIdentity") {
                try createWorkspaceTables(in: db)
            }

            if try db.tableExists("timeline") {
                let columns = try db.columns(in: "timeline").map { $0.name }
                try db.alter(table: "timeline") { table in
                    if !columns.contains("primaryWorkspaceId") {
                        table.add(column: "primaryWorkspaceId", .blob)
                            .references("workspace", onDelete: .setNull)
                    }
                    if !columns.contains("attachedWorkspaceIds") {
                        table.add(column: "attachedWorkspaceIds", .text).notNull().defaults(to: "[]")
                    }
                }
            }
        }

        // v17: Add toolCallId to conversationMessage (for 'tool' role messages)
        migrator.registerMigration("v17") { db in
            if try !db.columns(in: "conversationMessage").contains(where: {
                $0.name == "toolCallId"
            }) {
                try db.alter(table: "conversationMessage") { table in
                    table.add(column: "toolCallId", .text)
                }
            }
        }

        // v18: Remove legacy Note table
        migrator.registerMigration("v18") { _ in
            // Note table removal logic removed
        }

        // v19: Restore Note table
        // v19: Restore Note table (Removed)
        migrator.registerMigration("v19") { _ in
            // No-op
        }

        // v20: Add persona column to timeline
        migrator.registerMigration("v20") { db in
            if try !db.columns(in: "timeline").contains(where: { $0.name == "persona" }) {
                try db.alter(table: "timeline") { table in
                    table.add(column: "persona", .text)
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
                    BEFORE DELETE ON timeline
                    FOR EACH ROW
                    WHEN OLD.isArchived = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived timelines cannot be deleted');
                    END;
                """
            )

            try db.execute(
                sql: """
                    CREATE TRIGGER IF NOT EXISTS prevent_session_modification
                    BEFORE UPDATE ON timeline
                    FOR EACH ROW
                    WHEN OLD.isArchived = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived timelines cannot be modified');
                    END;
                """
            )

            try db.execute(
                sql: """
                    CREATE TRIGGER IF NOT EXISTS prevent_message_deletion
                    BEFORE DELETE ON conversationMessage
                    FOR EACH ROW
                    WHEN (SELECT isArchived FROM timeline WHERE id = OLD.timelineId) = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived messages cannot be deleted');
                    END;
                """
            )

            try db.execute(
                sql: """
                    CREATE TRIGGER IF NOT EXISTS prevent_message_modification
                    BEFORE UPDATE ON conversationMessage
                    FOR EACH ROW
                    WHEN (SELECT isArchived FROM timeline WHERE id = OLD.timelineId) = 1
                    BEGIN
                        SELECT RAISE(ABORT, 'Archived messages cannot be modified');
                    END;
                """
            )
        }

        // v22: Add timelineId to BackgroundJob table
        migrator.registerMigration("v22") { db in
            try db.drop(table: "job")

            try db.create(table: "job") { table in
                table.column("id", .blob).primaryKey()
                table.column("timelineId", .blob).notNull()
                    .references("timeline", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("description", .text)
                table.column("priority", .integer).notNull().defaults(to: 0)
                table.column("status", .text).notNull().defaults(to: "pending")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
            try db.create(index: "idx_job_session", on: "job", columns: ["timelineId"])
        }

        // v23: Add status to workspace table
        migrator.registerMigration("v23") { db in
            if try !db.columns(in: "workspace").contains(where: { $0.name == "status" }) {
                try db.alter(table: "workspace") { table in
                    table.add(column: "status", .text).notNull().defaults(to: "active")
                }
            }
        }

        // v24: Add agentId to BackgroundJob table
        migrator.registerMigration("v24") { db in
            try db.drop(table: "job")

            try db.create(table: "job") { table in
                table.column("id", .blob).primaryKey()
                table.column("timelineId", .blob).notNull()
                    .references("timeline", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("description", .text)
                table.column("priority", .integer).notNull().defaults(to: 0)
                table.column("agentId", .text).notNull().defaults(to: "default")
                table.column("status", .text).notNull().defaults(to: "pending")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
            try db.create(index: "idx_job_session", on: "job", columns: ["timelineId"])
            try db.create(index: "idx_job_agent", on: "job", columns: ["agentId"])
        }

        // v25: Add missing columns to BackgroundJob table
        migrator.registerMigration("v25") { db in
            try db.drop(table: "job")

            try db.create(table: "job") { table in
                table.column("id", .blob).primaryKey()
                table.column("timelineId", .blob).notNull()
                    .references("timeline", onDelete: .cascade)
                table.column("title", .text).notNull()
                table.column("description", .text)
                table.column("priority", .integer).notNull().defaults(to: 0)
                table.column("agentId", .text).notNull().defaults(to: "default")
                table.column("status", .text).notNull().defaults(to: "pending")
                table.column("createdAt", .datetime).notNull()
                table.column("updatedAt", .datetime).notNull()
                table.column("logs", .text).notNull().defaults(to: "[]")
                table.column("retryCount", .integer).notNull().defaults(to: 0)
                table.column("lastRetryAt", .datetime)
                table.column("nextRunAt", .datetime)
            }

            try db.create(index: "idx_job_status", on: "job", columns: ["status"])
            try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
            try db.create(index: "idx_job_session", on: "job", columns: ["timelineId"])
            try db.create(index: "idx_job_agent", on: "job", columns: ["agentId"])
        }

        // v26: Add parentId to BackgroundJob table for task trees
        migrator.registerMigration("v26") { db in
            if try !db.columns(in: "job").contains(where: { $0.name == "parentId" }) {
                try db.alter(table: "job") { table in
                    table.add(column: "parentId", .blob).references("job", onDelete: .cascade)
                }
            }
            try db.create(index: "idx_job_parent", on: "job", columns: ["parentId"])
        }

        // v27: Add agent table for simplified, data-driven msAgents
        migrator.registerMigration("v27") { db in
            try createMSAgentTable(in: db)

            // Seed with default agent
            let defaultMSAgent = MSAgent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                name: "Default Assistant",
                description: "A general purpose assistant focused on helpfulness and accuracy.",
                systemPrompt: """
                You are a helpful, intelligent, and efficient AI assistant named Monad.
                Your goal is to assist the user with their tasks while being concise and professional.
                """
            )
            try defaultMSAgent.insert(db)

            // Seed with coordinator agent
            let coordinatorMSAgent = MSAgent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                name: "MSAgent Coordinator",
                description: "Coordinates multiple msAgents and complex workflows.",
                systemPrompt: """
                You are the Monad Coordinator. Your role is to break down complex tasks into smaller sub-tasks
                and delegate them to specialized msAgents.
                """
            )
            try coordinatorMSAgent.insert(db)
        }

        // v28: Ensure tools column exists on workspace table
        migrator.registerMigration("v28") { db in
            if try db.tableExists("workspace") && !db.columns(in: "workspace").contains(where: { $0.name == "tools" }) {
                try db.alter(table: "workspace") { table in
                    table.add(column: "tools", .text).notNull().defaults(to: "[]")
                }
            }
        }

        // v29: Remove memoryId from conversationMessage
        migrator.registerMigration("v29") { db in
            if try db.columns(in: "conversationMessage").contains(where: { $0.name == "memoryId" }) {
                try db.alter(table: "conversationMessage") { table in
                    table.drop(column: "memoryId")
                }
            }
        }

        // v30: Add metadata to workspace table
        migrator.registerMigration("v30") { db in
            if try !db.columns(in: "workspace").contains(where: { $0.name == "metadata" }) {
                try db.alter(table: "workspace") { table in
                    table.add(column: "metadata", .text).notNull().defaults(to: "{}")
                }
            }
        }

        // v31: Rename conversationSession table to timeline (for existing databases)
        // Fresh installs (via v1 baseline) already have 'timeline'; this is a no-op for them.
        migrator.registerMigration("v31") { db in
            guard try db.tableExists("conversationSession") else { return }

            // 1. Rename the main conversation table
            try db.execute(sql: "ALTER TABLE conversationSession RENAME TO timeline")

            // 2. Rename sessionId → timelineId in conversationMessage
            if try db.columns(in: "conversationMessage").contains(where: { $0.name == "sessionId" }) {
                try db.execute(sql: "ALTER TABLE conversationMessage RENAME COLUMN sessionId TO timelineId")
            }

            // 3. Rename sessionId → timelineId in job table
            if try db.columns(in: "job").contains(where: { $0.name == "sessionId" }) {
                try db.execute(sql: "ALTER TABLE job RENAME COLUMN sessionId TO timelineId")
            }

            // 4. Replace old index names with new ones
            try db.execute(sql: "DROP INDEX IF EXISTS idx_message_session")
            try db.create(index: "idx_message_timeline", on: "conversationMessage", columns: ["timelineId"])

            try db.execute(sql: "DROP INDEX IF EXISTS idx_job_session")
            try db.create(index: "idx_job_timeline", on: "job", columns: ["timelineId"])
        }

        // v32: Add agentInstance table; extend timeline and conversationMessage
        migrator.registerMigration("v32") { db in
            // 1. Create agentInstance table
            if try !db.tableExists("agentInstance") {
                try createAgentInstanceTable(in: db)
            }

            // 2. Extend timeline table
            let timelineCols = try db.columns(in: "timeline").map { $0.name }
            try db.alter(table: "timeline") { table in
                if !timelineCols.contains("attachedAgentInstanceId") {
                    table.add(column: "attachedAgentInstanceId", .blob)
                }
                if !timelineCols.contains("isPrivate") {
                    table.add(column: "isPrivate", .boolean).notNull().defaults(to: false)
                }
                if !timelineCols.contains("ownerAgentInstanceId") {
                    table.add(column: "ownerAgentInstanceId", .blob)
                }
            }

            // 3. Extend conversationMessage table
            let msgCols = try db.columns(in: "conversationMessage").map { $0.name }
            try db.alter(table: "conversationMessage") { table in
                if !msgCols.contains("agentInstanceId") {
                    table.add(column: "agentInstanceId", .blob)
                }
                if !msgCols.contains("remoteDepth") {
                    table.add(column: "remoteDepth", .integer).notNull().defaults(to: 0)
                }
            }

            // 4. Indexes
            try db.create(
                index: "idx_timeline_agentInstance",
                on: "timeline",
                columns: ["attachedAgentInstanceId"],
                ifNotExists: true
            )
            try db.create(
                index: "idx_msg_agentInstance",
                on: "conversationMessage",
                columns: ["agentInstanceId"],
                ifNotExists: true
            )
        }
    }
}

import Foundation
import GRDB
import MonadShared

extension DatabaseSchema {
    // MARK: - Workspace Tables

    static func createWorkspaceTables(in db: Database) throws {
        // Client entity table
        try db.create(table: "clientIdentity") { table in
            table.column("id", .blob).primaryKey()
            table.column("hostname", .text).notNull()
            table.column("displayName", .text).notNull()
            table.column("platform", .text).notNull()
            table.column("registeredAt", .datetime).notNull()
            table.column("lastSeenAt", .datetime)
        }

        // Workspace table
        try db.create(table: "workspace") { table in
            table.column("id", .blob).primaryKey()
            table.column("uri", .text).notNull().unique()
            table.column("hostType", .text).notNull()
            table.column("ownerId", .blob).references("clientIdentity", onDelete: .setNull)
            table.column("tools", .text).notNull().defaults(to: "[]")
            table.column("rootPath", .text)
            table.column("trustLevel", .text).notNull().defaults(to: "full")
            table.column("lastModifiedBy", .blob)
            table.column("status", .text).notNull().defaults(to: "active")
            table.column("metadata", .text).notNull().defaults(to: "{}")
            table.column("createdAt", .datetime).notNull()
        }

        // Workspace tools (tool definitions per workspace)
        try db.create(table: "workspaceTool") { table in
            table.column("id", .blob).primaryKey()
            table.column("workspaceId", .blob).notNull()
                .references("workspace", onDelete: .cascade)
            table.column("toolId", .text).notNull()
            table.column("isKnown", .boolean).notNull()
            table.column("definition", .text)
        }
        try db.create(
            index: "idx_workspaceTool_workspace",
            on: "workspaceTool",
            columns: ["workspaceId"]
        )

        // Workspace locks
        try db.create(table: "workspaceLock") { table in
            table.column("workspaceId", .blob).primaryKey()
                .references("workspace", onDelete: .cascade)
            table.column("heldBy", .blob).notNull()
            table.column("acquiredAt", .datetime).notNull()
        }
    }

    // MARK: - Conversation Tables

    static func createConversationTables(in db: Database) throws {
        // Conversation sessions
        try db.create(table: "timeline") { table in
            table.primaryKey("id", .blob).notNull()
            table.column("title", .text).notNull()
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("isArchived", .boolean).notNull().defaults(to: false)
            table.column("workingDirectory", .text)
            table.column("attachedWorkspaceIds", .text).notNull().defaults(to: "[]")
            table.column("persona", .text)
            table.column("attachedAgentInstanceId", .blob)
            table.column("isPrivate", .boolean).notNull().defaults(to: false)
        }

        // Conversation messages
        try db.create(table: "conversationMessage") { table in
            table.primaryKey("id", .blob).notNull()
            table.column("timelineId", .blob).notNull()
                .references("timeline", onDelete: .cascade)
            table.column("role", .text).notNull()
            table.column("content", .text).notNull()
            table.column("timestamp", .datetime).notNull()
            table.column("recalledMemories", .text).notNull().defaults(to: "[]")
            table.column("parentId", .blob).references("conversationMessage", onDelete: .setNull)
            table.column("think", .text)
            table.column("toolCalls", .text).notNull().defaults(to: "[]")
            table.column("toolCallId", .text)
            table.column("agentInstanceId", .blob)
            table.column("remoteDepth", .integer).notNull().defaults(to: 0)
        }

        // Indexes for timeline
        try db.create(
            index: "idx_timeline_agentInstance",
            on: "timeline",
            columns: ["attachedAgentInstanceId"],
            ifNotExists: true
        )

        // Indexes for messages
        try db.create(
            index: "idx_message_timeline",
            on: "conversationMessage",
            columns: ["timelineId"]
        )
        try db.create(
            index: "idx_message_timestamp",
            on: "conversationMessage",
            columns: ["timestamp"]
        )
        try db.create(
            index: "idx_msg_agentInstance",
            on: "conversationMessage",
            columns: ["agentInstanceId"],
            ifNotExists: true
        )
    }

    // MARK: - Memory Table

    static func createMemoryTable(in db: Database) throws {
        try db.create(table: "memory") { table in
            table.primaryKey("id", .blob).notNull()
            table.column("title", .text).notNull()
            table.column("content", .text).notNull()
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("tags", .text).notNull().defaults(to: "")
            table.column("metadata", .text).notNull().defaults(to: "{}")
            table.column("embedding", .text).notNull().defaults(to: "[]")
        }
    }

    // MARK: - Job Table

    static func createJobTable(in db: Database) throws {
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
            table.column("parentId", .blob).references("job", onDelete: .cascade)
        }
        try db.create(index: "idx_job_status", on: "job", columns: ["status"])
        try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
        try db.create(index: "idx_job_timeline", on: "job", columns: ["timelineId"])
        try db.create(index: "idx_job_agent", on: "job", columns: ["agentId"])
        try db.create(index: "idx_job_parent", on: "job", columns: ["parentId"])
    }

    // MARK: - Compactification Node Table

    static func createCompactificationNodeTable(in db: Database) throws {
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

    // MARK: - AgentInstance Table

    static func createAgentInstanceTable(in db: Database) throws {
        try db.create(table: "agentInstance") { table in
            table.column("id", .blob).primaryKey()
            table.column("name", .text).notNull()
            table.column("description", .text).notNull().defaults(to: "")
            table.column("primaryWorkspaceId", .blob)
                .references("workspace", onDelete: .setNull)
            table.column("privateTimelineId", .blob).notNull()
            table.column("lastActiveAt", .datetime).notNull()
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("metadata", .text).notNull().defaults(to: "{}")
        }
        try db.create(
            index: "idx_agentInstance_privateTimeline",
            on: "agentInstance",
            columns: ["privateTimelineId"],
            ifNotExists: true
        )
    }

    // MARK: - AgentTemplate Table

    static func createAgentTemplateTable(in db: Database) throws {
        try db.create(table: "agent") { table in
            table.column("id", .text).primaryKey()
            table.column("name", .text).notNull()
            table.column("description", .text).notNull()
            table.column("systemPrompt", .text).notNull()
            table.column("personaPrompt", .text)
            table.column("guardrailsPrompt", .text)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("workspaceFilesSeed", .text)
        }
    }

    // MARK: - Immutability Triggers

    static func createImmutabilityTriggers(in db: Database) throws {
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

    // MARK: - Seed Data

    static func seedDefaultAgentTemplates(in db: Database) throws {
        let defaultAgent = AgentTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Default Assistant",
            description: "A general purpose assistant focused on helpfulness and accuracy.",
            systemPrompt: """
            You are a helpful, intelligent, and efficient AI assistant named Monad.
            Your goal is to assist the user with their tasks while being concise and professional.
            """
        )
        try defaultAgent.insert(db)

        let coordinatorAgent = AgentTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "AgentTemplate Coordinator",
            description: "Coordinates multiple agentTemplates and complex workflows.",
            systemPrompt: """
            You are the Monad Coordinator. Your role is to break down complex tasks into smaller sub-tasks
            and delegate them to specialized agentTemplates.
            """
        )
        try coordinatorAgent.insert(db)
    }
}

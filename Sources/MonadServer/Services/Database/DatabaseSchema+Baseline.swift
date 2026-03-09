import Foundation
import GRDB
import MonadShared

extension DatabaseSchema {
    // MARK: - Workspace Tables

    static func createWorkspaceTables(in db: Database) throws {
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
            t.column("tools", .text).notNull().defaults(to: "[]")
            t.column("rootPath", .text)
            t.column("trustLevel", .text).notNull().defaults(to: "full")
            t.column("lastModifiedBy", .blob)
            t.column("status", .text).notNull().defaults(to: "active")
            t.column("metadata", .text).notNull().defaults(to: "{}")
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
            columns: ["workspaceId"]
        )

        // Workspace locks
        try db.create(table: "workspaceLock") { t in
            t.column("workspaceId", .blob).primaryKey()
                .references("workspace", onDelete: .cascade)
            t.column("heldBy", .blob).notNull()
            t.column("acquiredAt", .datetime).notNull()
        }
    }

    // MARK: - Conversation Tables

    static func createConversationTables(in db: Database) throws {
        // Conversation sessions
        try db.create(table: "timeline") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("title", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("isArchived", .boolean).notNull().defaults(to: false)
            t.column("tags", .text).notNull().defaults(to: "")
            t.column("workingDirectory", .text)
            t.column("primaryWorkspaceId", .blob)
                .references("workspace", onDelete: .setNull)
            t.column("attachedWorkspaceIds", .text).notNull().defaults(to: "[]")
            t.column("persona", .text)
            t.column("attachedAgentInstanceId", .blob)
            t.column("isPrivate", .boolean).notNull().defaults(to: false)
            t.column("ownerAgentInstanceId", .blob)
        }

        // Conversation messages
        try db.create(table: "conversationMessage") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("timelineId", .blob).notNull()
                .references("timeline", onDelete: .cascade)
            t.column("role", .text).notNull()
            t.column("content", .text).notNull()
            t.column("timestamp", .datetime).notNull()
            t.column("recalledMemories", .text).notNull().defaults(to: "[]")
            t.column("parentId", .blob).references("conversationMessage", onDelete: .setNull)
            t.column("think", .text)
            t.column("toolCalls", .text).notNull().defaults(to: "[]")
            t.column("toolCallId", .text)
            t.column("agentInstanceId", .blob)
            t.column("remoteDepth", .integer).notNull().defaults(to: 0)
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
        try db.create(table: "memory") { t in
            t.primaryKey("id", .blob).notNull()
            t.column("title", .text).notNull()
            t.column("content", .text).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("tags", .text).notNull().defaults(to: "")
            t.column("metadata", .text).notNull().defaults(to: "{}")
            t.column("embedding", .text).notNull().defaults(to: "[]")
        }
    }

    // MARK: - Job Table

    static func createJobTable(in db: Database) throws {
        try db.create(table: "job") { t in
            t.column("id", .blob).primaryKey()
            t.column("timelineId", .blob).notNull()
                .references("timeline", onDelete: .cascade)
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
            t.column("parentId", .blob).references("job", onDelete: .cascade)
        }
        try db.create(index: "idx_job_status", on: "job", columns: ["status"])
        try db.create(index: "idx_job_priority", on: "job", columns: ["priority"])
        try db.create(index: "idx_job_timeline", on: "job", columns: ["timelineId"])
        try db.create(index: "idx_job_agent", on: "job", columns: ["agentId"])
        try db.create(index: "idx_job_parent", on: "job", columns: ["parentId"])
    }

    // MARK: - Compactification Node Table

    static func createCompactificationNodeTable(in db: Database) throws {
        try db.create(table: "compactificationNode") { t in
            t.column("id", .blob).primaryKey()
            t.column("timelineId", .blob).notNull()
                .references("timeline", onDelete: .cascade)
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
            columns: ["timelineId"]
        )
    }

    // MARK: - AgentInstance Table

    static func createAgentInstanceTable(in db: Database) throws {
        try db.create(table: "agentInstance") { t in
            t.column("id", .blob).primaryKey()
            t.column("name", .text).notNull()
            t.column("description", .text).notNull().defaults(to: "")
            t.column("primaryWorkspaceId", .blob)
                .references("workspace", onDelete: .setNull)
            t.column("privateTimelineId", .blob).notNull()
            t.column("lastActiveAt", .datetime).notNull()
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("metadata", .text).notNull().defaults(to: "{}")
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
        try db.create(table: "agent") { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("description", .text).notNull()
            t.column("systemPrompt", .text).notNull()
            t.column("personaPrompt", .text)
            t.column("guardrailsPrompt", .text)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
            t.column("workspaceFilesSeed", .text)
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

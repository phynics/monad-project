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
}

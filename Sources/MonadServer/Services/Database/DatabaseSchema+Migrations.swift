import Foundation
import GRDB
import PositronicKit
import PKShared
import MonadShared

public extension DatabaseSchema {
    /// Register all migrations
    static func registerMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { db in
            try createWorkspaceTables(in: db)
            try createConversationTables(in: db)
            try createMemoryTable(in: db)
            try createJobTable(in: db)
            try createCompactificationNodeTable(in: db)
            try createAgentTemplateTable(in: db)
            try createAgentInstanceTable(in: db)
            try createImmutabilityTriggers(in: db)
            try seedDefaultAgentTemplates(in: db)
        }

        migrator.registerMigration("v2") { db in
            // Add embedding column to memory table if it doesn't exist
            // (it won't for users who ran v1 before it was added to baseline)
            if try !db.columns(in: "memory").contains(where: { $0.name == "embedding" }) {
                try db.alter(table: "memory") { table in
                    table.add(column: "embedding", .text).notNull().defaults(to: "[]")
                }
            }
        }

        migrator.registerMigration("v3") { db in
            try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS key_value_store (
                key   TEXT PRIMARY KEY NOT NULL,
                value BLOB NOT NULL
            )
            """)
        }

        migrator.registerMigration("v4") { db in
            if try !db.columns(in: "conversationMessage").contains(where: { $0.name == "snapshotData" }) {
                try db.alter(table: "conversationMessage") { table in
                    table.add(column: "snapshotData", .blob)
                }
            }
        }

        migrator.registerMigration("v5") { db in
            if try db.tableExists("clientIdentity") && !(try db.tableExists("requestOrigin")) {
                try db.execute(sql: "ALTER TABLE clientIdentity RENAME TO requestOrigin")
            }

            guard try db.tableExists("workspace") else {
                return
            }

            let workspaceColumns = try db.columns(in: "workspace").map(\.name)

            if workspaceColumns.contains("hostType") && !workspaceColumns.contains("location") {
                try db.execute(sql: "ALTER TABLE workspace RENAME COLUMN hostType TO location")
            }

            if workspaceColumns.contains("ownerId") && !workspaceColumns.contains("originId") {
                try db.execute(sql: "ALTER TABLE workspace RENAME COLUMN ownerId TO originId")
            }
        }

        migrator.registerMigration("v6") { db in
            guard try db.tableExists("workspace"), try db.tableExists("requestOrigin") else {
                return
            }

            try db.execute(sql: """
                UPDATE workspace
                SET originId = NULL
                WHERE originId IS NOT NULL
                  AND originId NOT IN (SELECT id FROM requestOrigin)
            """)
        }

        migrator.registerMigration("v7") { db in
            guard try db.tableExists("workspaceTool") else {
                return
            }

            try db.execute(sql: """
                DELETE FROM workspaceTool
                WHERE rowid NOT IN (
                    SELECT MIN(rowid)
                    FROM workspaceTool
                    GROUP BY workspaceId, toolId
                )
            """)

            try db.create(
                index: "idx_workspaceTool_unique_membership",
                on: "workspaceTool",
                columns: ["workspaceId", "toolId"],
                unique: true,
                ifNotExists: true
            )
        }
    }
}

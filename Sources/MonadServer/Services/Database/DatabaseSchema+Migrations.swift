import Foundation
import GRDB
import MonadCore
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
            // Add embedding column to memory table if it doesn't exist (it won't for users who ran v1 before it was added to baseline)
            if try !db.columns(in: "memory").contains(where: { $0.name == "embedding" }) {
                try db.alter(table: "memory") { t in
                    t.add(column: "embedding", .text).notNull().defaults(to: "[]")
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
    }
}

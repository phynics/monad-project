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
    }
}

import MonadShared
import Foundation
import GRDB
import Testing
@testable import MonadCore

@Suite(.serialized)
struct MigrationTests {

    @Test("Verify v2 migration adds embedding column to existing v1 database")
    func testV2Migration() async throws {
        // 1. Setup in-memory DB
        let queue = try DatabaseQueue()

        // 2. Setup "old" state using a migrator that defines v1 WITHOUT embedding
        var oldMigrator = DatabaseMigrator()
        oldMigrator.registerMigration("v1") { db in
            try db.create(table: "memory") { t in
                t.primaryKey("id", .blob).notNull()
                t.column("title", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("tags", .text).notNull().defaults(to: "")
                t.column("metadata", .text).notNull().defaults(to: "")
            }
            // Create other tables minimal versions to satisfy potential FKs if needed
            try db.create(table: "conversationSession") { t in
                t.primaryKey("id", .blob).notNull()
            }
            try db.create(table: "conversationMessage") { t in
                t.primaryKey("id", .blob).notNull()
                t.column("sessionId", .blob).notNull().references("conversationSession")
            }
        }
        try oldMigrator.migrate(queue)

        // 3. Now verify column is missing
        try await queue.read { db in
            let columns = try db.columns(in: "memory")
            #expect(!columns.contains(where: { $0.name == "embedding" }))
        }

        // 4. Run the REAL migrations (which includes v1 and v2)
        // Since v1 is already marked as applied by oldMigrator, it should skip v1 and run v2.
        var newMigrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &newMigrator)

        try newMigrator.migrate(queue)

        // 5. Verify column exists
        try await queue.read { db in
            let columns = try db.columns(in: "memory")
            #expect(columns.contains(where: { $0.name == "embedding" }))
        }

        // 6. Verify we can insert a Memory
        let memory = Memory(title: "Test", content: "Content", embedding: [0.1, 0.2])
        try await queue.write { db in
            try memory.save(db)
        }
    }
}

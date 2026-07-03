import PKShared
import MonadShared
import PositronicKit
import Foundation
import GRDB
import Testing
import MonadServer

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
            try db.create(table: "timeline") { t in
                t.primaryKey("id", .blob).notNull()
                t.column("isArchived", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "conversationMessage") { t in
                t.primaryKey("id", .blob).notNull()
                t.column("timelineId", .blob).notNull().references("timeline")
                t.column("role", .text).notNull().defaults(to: "user")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("timestamp", .datetime).notNull().defaults(to: Date())
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
        // Since we are using the 'real' Memory model but a 'mock' v1 schema,
        // we should use a manual insert to avoid issues with missing columns in the mock schema.
        try await queue.write { db in
            try db.execute(sql: """
                INSERT INTO memory (id, title, content, createdAt, updatedAt, tags, metadata, embedding)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [UUID(), "Test", "Content", Date(), Date(), "[]", "{}", "[]"])
        }
    }

    @Test("Verify latest schema uses request-origin and location column names")
    func latestSchema_usesRequestOriginTerminology() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)

        try migrator.migrate(queue)

        try await queue.read { db in
            #expect(try db.tableExists("requestOrigin"))
            #expect(!(try db.tableExists("clientIdentity")))

            let workspaceColumns = try db.columns(in: "workspace").map(\.name)
            #expect(workspaceColumns.contains("location"))
            #expect(workspaceColumns.contains("originId"))
            #expect(!workspaceColumns.contains("hostType"))
            #expect(!workspaceColumns.contains("ownerId"))
        }
    }

    @Test("v6 migration clears orphaned workspace origins after request-origin rename")
    func migration_repairsOrphanedWorkspaceOrigins() async throws {
        let queue = try DatabaseQueue()

        var oldMigrator = DatabaseMigrator()
        oldMigrator.registerMigration("v1") { db in
            try db.create(table: "clientIdentity") { table in
                table.column("id", .blob).primaryKey()
                table.column("hostname", .text).notNull()
                table.column("displayName", .text).notNull()
                table.column("platform", .text).notNull()
                table.column("registeredAt", .datetime).notNull()
                table.column("lastSeenAt", .datetime)
            }

            try db.create(table: "workspace") { table in
                table.column("id", .blob).primaryKey()
                table.column("uri", .text).notNull().unique()
                table.column("hostType", .text).notNull()
                table.column("ownerId", .blob)
                table.column("tools", .text).notNull().defaults(to: "[]")
                table.column("rootPath", .text)
                table.column("trustLevel", .text).notNull().defaults(to: "full")
                table.column("lastModifiedBy", .blob)
                table.column("status", .text).notNull().defaults(to: "active")
                table.column("metadata", .text).notNull().defaults(to: "{}")
                table.column("createdAt", .datetime).notNull()
            }
        }
        oldMigrator.registerMigration("v2") { _ in }
        oldMigrator.registerMigration("v3") { _ in }
        oldMigrator.registerMigration("v4") { _ in }
        oldMigrator.registerMigration("v5") { db in
            try db.execute(sql: "ALTER TABLE clientIdentity RENAME TO requestOrigin")
            try db.execute(sql: "ALTER TABLE workspace RENAME COLUMN hostType TO location")
            try db.execute(sql: "ALTER TABLE workspace RENAME COLUMN ownerId TO originId")
        }
        try oldMigrator.migrate(queue)

        let orphanedOriginId = UUID()
        try await queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO workspace (id, uri, location, originId, tools, trustLevel, status, metadata, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID(),
                    "atkn-mbp.local:~",
                    "client",
                    orphanedOriginId,
                    "[]",
                    "full",
                    "active",
                    "{}",
                    Date(),
                ]
            )
        }

        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        try await queue.read { db in
            let workspace = try #require(try WorkspaceReference.fetchOne(db))
            #expect(workspace.originId == nil)
        }
    }

    @Test("v8 migration adds nullable status column to conversationMessage (MON-1)")
    func v8Migration_addsStatusColumn() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        try await queue.read { db in
            let statusColumn = try db.columns(in: "conversationMessage").first(where: { $0.name == "status" })
            #expect(statusColumn != nil, "v8 must add a status column to conversationMessage")
            // Nullable: STAB-1's nil == .complete must round-trip, so the column cannot be NOT NULL.
            #expect(statusColumn?.isNotNull == false, "status column must be nullable (nil == .complete)")
        }
    }

    @Test("ConversationMessage status round-trips through the database (MON-1)")
    func conversationMessageStatus_roundTrips() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        let timelineStore = TimelineRepository(dbQueue: queue)
        let messageStore = MessageRepository(dbQueue: queue)

        let session = Timeline(title: "MON-1 round-trip")
        try await timelineStore.saveTimeline(session)

        // A partial (failed-stream) assistant turn must persist and reload with its tag.
        let partial = ConversationMessage(
            timelineId: session.id,
            role: .assistant,
            content: "partial response",
            status: .partial
        )
        try await messageStore.saveMessage(partial)

        let fetchedPartial = try await messageStore.fetchMessages(for: session.id).first(where: { $0.id == partial.id })
        #expect(fetchedPartial?.status == .partial)

        // A complete (nil-status) assistant turn round-trips as nil — byte-identical to
        // pre-STAB-1 rows and to the success path.
        let complete = ConversationMessage(
            timelineId: session.id,
            role: .assistant,
            content: "complete response"
        )
        try await messageStore.saveMessage(complete)

        let fetchedComplete = try await messageStore.fetchMessages(for: session.id).first(where: { $0.id == complete.id })
        #expect(fetchedComplete?.status == nil)
    }

    @Test("database reset fallback is not offered for non-integrity open failures")
    func databaseInitialization_doesNotOfferResetForOpenFailure() throws {
        let badPath = "/definitely-missing-parent-\(UUID().uuidString)/monad.sqlite"
        var callbackInvoked = false

        #expect(throws: Error.self) {
            _ = try DatabaseManager.create(path: badPath, onInitializationFailure: { _, _ in
                callbackInvoked = true
                return true
            })
        }

        #expect(callbackInvoked == false)
    }

    @Test("Database initialization can reset an unrecoverable legacy database")
    func databaseInitialization_canResetLegacyDatabase() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let databasePath = tempDir.appendingPathComponent("monad.sqlite").path
        var configuration = Configuration()
        configuration.foreignKeysEnabled = false
        let queue = try DatabaseQueue(path: databasePath, configuration: configuration)

        var oldMigrator = DatabaseMigrator()
        oldMigrator.registerMigration("v1") { db in
            try db.create(table: "clientIdentity") { table in
                table.column("id", .blob).primaryKey()
                table.column("hostname", .text).notNull()
                table.column("displayName", .text).notNull()
                table.column("platform", .text).notNull()
                table.column("registeredAt", .datetime).notNull()
                table.column("lastSeenAt", .datetime)
            }

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
        }
        oldMigrator.registerMigration("v2") { _ in }
        oldMigrator.registerMigration("v3") { _ in }
        oldMigrator.registerMigration("v4") { _ in }
        try oldMigrator.migrate(queue)

        try await queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO workspace (id, uri, hostType, ownerId, tools, trustLevel, status, metadata, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    UUID(),
                    "atkn-mbp.local:~",
                    "client",
                    UUID(),
                    "[]",
                    "full",
                    "active",
                    "{}",
                    Date(),
                ]
            )
        }

        let manager = try DatabaseManager.create(path: databasePath, onInitializationFailure: { _, failingPath in
            #expect(failingPath == databasePath)
            return true
        })

        try await manager.dbQueue.read { db in
            #expect(try db.tableExists("requestOrigin"))
            #expect(!(try db.tableExists("clientIdentity")))
            let workspaces = try WorkspaceReference.fetchCount(db)
            #expect(workspaces == 0)
        }
    }
}

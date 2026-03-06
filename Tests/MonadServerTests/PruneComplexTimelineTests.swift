import MonadShared
import MonadCore
import Foundation
import GRDB
import MonadServer
import Testing

@Suite(.serialized)
@MainActor
struct PruneComplexSessionTests {
    private let persistence: PersistenceService
    private let dbQueue: DatabaseQueue

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        dbQueue = queue
    }

    @Test("pruneTimelines should handle archived sessions with complex dependencies")
    func testPruneComplexDependencies() async throws {
        // 1. Create archived session
        var archivedSession = Timeline(title: "Archived Session")
        archivedSession.isArchived = true
        archivedSession.updatedAt = Date().addingTimeInterval(-3600)
        try await persistence.saveTimeline(archivedSession)

        // Add dependencies for archived session
        // Message (should be protected by trigger)
        let archivedMsg = ConversationMessage(
            timelineId: archivedSession.id,
            role: .user,
            content: "Archived Msg",
            timestamp: Date().addingTimeInterval(-3600)
        )
        try await persistence.saveMessage(archivedMsg)

        // Compactification Node (cascade delete, but session deletion should be blocked)
        let archivedSessionId = archivedSession.id
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO compactificationNode (id, timelineId, type, summary, displayHint, childIds, metadata, createdAt)
                    VALUES (?, ?, 'summary', 'Summary', 'hint', '[]', '{}', ?)
                    """,
                arguments: [UUID(), archivedSessionId, Date()]
            )
        }

        // 2. Create non-archived session
        var liveSession = Timeline(title: "Live Session")
        liveSession.isArchived = false
        liveSession.updatedAt = Date().addingTimeInterval(-3600)
        try await persistence.saveTimeline(liveSession)

        // Add dependencies for live session
        // Message (should be deleted by cascade)
        let liveMsg = ConversationMessage(
            timelineId: liveSession.id,
            role: .user,
            content: "Live Msg",
            timestamp: Date().addingTimeInterval(-3600)
        )
        try await persistence.saveMessage(liveMsg)

        // Compactification Node (should be deleted by cascade)
        let liveSessionId = liveSession.id
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO compactificationNode (id, timelineId, type, summary, displayHint, childIds, metadata, createdAt)
                    VALUES (?, ?, 'summary', 'Summary', 'hint', '[]', '{}', ?)
                    """,
                arguments: [UUID(), liveSessionId, Date()]
            )
        }

        // 3. Call pruneTimelines (olderThan: 0 = all)
        let count = try await persistence.pruneTimelines(olderThan: 0, dryRun: false)

        // 4. Verify results
        #expect(count == 1)

        // Live session gone
        let fetchedLive = try await persistence.fetchTimeline(id: liveSession.id)
        #expect(fetchedLive == nil)

        // Live dependencies gone (check manual query for compactificationNode)
        let liveID = liveSession.id
        let liveNodes = try await dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM compactificationNode WHERE timelineId = ?",
                arguments: [liveID]) ?? 0
        }
        #expect(liveNodes == 0)

        // Archived session remains
        let fetchedArchived = try await persistence.fetchTimeline(id: archivedSession.id)
        #expect(fetchedArchived != nil)

        // Archived dependencies remain
        let archivedID = archivedSession.id
        let archivedNodes = try await dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM compactificationNode WHERE timelineId = ?",
                arguments: [archivedID]) ?? 0
        }
        #expect(archivedNodes == 1)
    }
}

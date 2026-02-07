import Foundation
import GRDB
import MonadCore
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

    @Test("pruneSessions should handle archived sessions with complex dependencies")
    func testPruneComplexDependencies() async throws {
        // 1. Create archived session
        var archivedSession = ConversationSession(title: "Archived Session")
        archivedSession.isArchived = true
        archivedSession.updatedAt = Date().addingTimeInterval(-3600)
        try await persistence.saveSession(archivedSession)

        // Add dependencies for archived session
        // Message (should be protected by trigger)
        let archivedMsg = ConversationMessage(
            sessionId: archivedSession.id,
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
                    INSERT INTO compactificationNode (id, sessionId, type, summary, displayHint, childIds, metadata, createdAt)
                    VALUES (?, ?, 'summary', 'Summary', 'hint', '[]', '{}', ?)
                    """,
                arguments: [UUID(), archivedSessionId, Date()]
            )
        }

        // 2. Create non-archived session
        var liveSession = ConversationSession(title: "Live Session")
        liveSession.isArchived = false
        liveSession.updatedAt = Date().addingTimeInterval(-3600)
        try await persistence.saveSession(liveSession)

        // Add dependencies for live session
        // Message (should be deleted by cascade)
        let liveMsg = ConversationMessage(
            sessionId: liveSession.id,
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
                    INSERT INTO compactificationNode (id, sessionId, type, summary, displayHint, childIds, metadata, createdAt)
                    VALUES (?, ?, 'summary', 'Summary', 'hint', '[]', '{}', ?)
                    """,
                arguments: [UUID(), liveSessionId, Date()]
            )
        }

        // 3. Call pruneSessions (olderThan: 0 = all)
        let count = try await persistence.pruneSessions(olderThan: 0, dryRun: false)

        // 4. Verify results
        #expect(count == 1)

        // Live session gone
        let fetchedLive = try await persistence.fetchSession(id: liveSession.id)
        #expect(fetchedLive == nil)

        // Live dependencies gone (check manual query for compactificationNode)
        let liveID = liveSession.id
        let liveNodes = try await dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM compactificationNode WHERE sessionId = ?",
                arguments: [liveID]) ?? 0
        }
        #expect(liveNodes == 0)

        // Archived session remains
        let fetchedArchived = try await persistence.fetchSession(id: archivedSession.id)
        #expect(fetchedArchived != nil)

        // Archived dependencies remain
        let archivedID = archivedSession.id
        let archivedNodes = try await dbQueue.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM compactificationNode WHERE sessionId = ?",
                arguments: [archivedID]) ?? 0
        }
        #expect(archivedNodes == 1)
    }
}

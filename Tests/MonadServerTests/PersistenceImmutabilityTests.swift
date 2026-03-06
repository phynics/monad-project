import MonadShared
import MonadCore
import Foundation
import GRDB
import Testing
import MonadServer

@Suite(.serialized)
@MainActor
struct PersistenceImmutabilityTests {
    private let persistence: PersistenceService
    private let dbQueue: DatabaseQueue

    init() async throws {
        // Use an in-memory database for testing
        let queue = try DatabaseQueue()
        // Register migrations
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        dbQueue = queue
    }

    @Test("Test that archived messages cannot be deleted or modified")
    func archiveImmutability() async throws {
        var session = Timeline(title: "Archived Session")
        session.isArchived = true
        try await persistence.saveTimeline(session)

        let message = ConversationMessage(
            timelineId: session.id,
            role: .user,
            content: "Permanent Message"
        )
        try await persistence.saveMessage(message)

        let messageId = message.id
        let timelineId = session.id

        // Attempt to delete message
        await #expect(throws: Error.self) {
            try await dbQueue.write { db in
                try db.execute(sql: "DELETE FROM conversationMessage WHERE id = ?", arguments: [messageId])
            }
        }

        // Attempt to update message content
        await #expect(throws: Error.self) {
            try await dbQueue.write { db in
                try db.execute(sql: "UPDATE conversationMessage SET content = 'Changed' WHERE id = ?", arguments: [messageId])
            }
        }

        // Verify message is unchanged
        let fetchedMessages = try await persistence.fetchMessages(for: timelineId)
        #expect(fetchedMessages.count == 1)
        #expect(fetchedMessages.first?.content == "Permanent Message")
    }

    @Test("Test that non-archived messages CAN be deleted or modified")
    func nonArchivedImmutability() async throws {
        var session = Timeline(title: "Live Session")
        session.isArchived = false
        try await persistence.saveTimeline(session)

        let message = ConversationMessage(
            timelineId: session.id,
            role: .user,
            content: "Temporary Message"
        )
        try await persistence.saveMessage(message)

        let messageId = message.id
        let timelineId = session.id

        // Attempt to update message content - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE conversationMessage SET content = 'Changed' WHERE id = ?", arguments: [messageId])
        }

        // Attempt to delete message - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM conversationMessage WHERE id = ?", arguments: [messageId])
        }

        // Verify message is gone
        let fetchedMessages = try await persistence.fetchMessages(for: timelineId)
        #expect(fetchedMessages.isEmpty)
    }

    @Test("Test that archived sessions cannot be deleted or modified")
    func sessionImmutability() async throws {
        var session = Timeline(title: "Permanent Session")
        session.isArchived = true
        try await persistence.saveTimeline(session)

        let timelineId = session.id

        // Attempt to delete session
        await #expect(throws: Error.self) {
            try await dbQueue.write { db in
                try db.execute(sql: "DELETE FROM timeline WHERE id = ?", arguments: [timelineId])
            }
        }

        // Attempt to update session title
        await #expect(throws: Error.self) {
            try await dbQueue.write { db in
                try db.execute(sql: "UPDATE timeline SET title = 'Changed' WHERE id = ?", arguments: [timelineId])
            }
        }
    }

    @Test("Test that non-archived sessions CAN be deleted or modified")
    func nonArchivedSessionImmutability() async throws {
        var session = Timeline(title: "Temporary Session")
        session.isArchived = false
        try await persistence.saveTimeline(session)

        let timelineId = session.id

        // Attempt to update session title - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE timeline SET title = 'Changed' WHERE id = ?", arguments: [timelineId])
        }

        // Attempt to delete session - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM timeline WHERE id = ?", arguments: [timelineId])
        }

        let fetched = try await persistence.fetchTimeline(id: timelineId)
        #expect(fetched == nil)
    }
}

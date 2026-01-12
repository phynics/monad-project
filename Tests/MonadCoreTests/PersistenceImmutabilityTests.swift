import Foundation
import GRDB
import MonadCore
import Testing

@testable import MonadCore

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

    @Test("Test that notes cannot be deleted")
    func noteDeletionPrevention() async throws {
        let note = Note(name: "Protected Note", content: "Cannot be deleted")
        try await persistence.saveNote(note)

        let noteId = note.id
        // Attempt to delete via PersistenceService
        // Initially this might success or throw if isReadonly is true.
        // But the requirement is that ALL notes cannot be deleted.
        
        // Let's try raw SQL to bypass any service-level checks
        await #expect(throws: Error.self) {
            try await dbQueue.write { db in
                try db.execute(sql: "DELETE FROM note WHERE id = ?", arguments: [noteId])
            }
        }
        
        // Verify it still exists
        let fetched = try await persistence.fetchNote(id: noteId)
        #expect(fetched != nil)
    }

    @Test("Test that archived messages cannot be deleted or modified")
    func archiveImmutability() async throws {
        var session = ConversationSession(title: "Archived Session")
        session.isArchived = true
        try await persistence.saveSession(session)

        let message = ConversationMessage(
            sessionId: session.id,
            role: .user,
            content: "Permanent Message"
        )
        try await persistence.saveMessage(message)

        let messageId = message.id
        let sessionId = session.id

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
        let fetchedMessages = try await persistence.fetchMessages(for: sessionId)
        #expect(fetchedMessages.count == 1)
        #expect(fetchedMessages.first?.content == "Permanent Message")
    }

    @Test("Test that non-archived messages CAN be deleted or modified")
    func nonArchivedImmutability() async throws {
        var session = ConversationSession(title: "Live Session")
        session.isArchived = false
        try await persistence.saveSession(session)

        let message = ConversationMessage(
            sessionId: session.id,
            role: .user,
            content: "Temporary Message"
        )
        try await persistence.saveMessage(message)

        let messageId = message.id
        let sessionId = session.id

        // Attempt to update message content - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE conversationMessage SET content = 'Changed' WHERE id = ?", arguments: [messageId])
        }

        // Attempt to delete message - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM conversationMessage WHERE id = ?", arguments: [messageId])
        }

        // Verify message is gone
        let fetchedMessages = try await persistence.fetchMessages(for: sessionId)
        #expect(fetchedMessages.isEmpty)
    }
    
    @Test("Test that archived sessions cannot be deleted or modified")
    func sessionImmutability() async throws {
        var session = ConversationSession(title: "Permanent Session")
        session.isArchived = true
        try await persistence.saveSession(session)
        
        let sessionId = session.id
        
        // Attempt to delete session
        await #expect(throws: Error.self) {
            try await dbQueue.write { db in
                try db.execute(sql: "DELETE FROM conversationSession WHERE id = ?", arguments: [sessionId])
            }
        }
        
        // Attempt to update session title
        await #expect(throws: Error.self) {
            try await dbQueue.write { db in
                try db.execute(sql: "UPDATE conversationSession SET title = 'Changed' WHERE id = ?", arguments: [sessionId])
            }
        }
    }

    @Test("Test that non-archived sessions CAN be deleted or modified")
    func nonArchivedSessionImmutability() async throws {
        var session = ConversationSession(title: "Temporary Session")
        session.isArchived = false
        try await persistence.saveSession(session)
        
        let sessionId = session.id
        
        // Attempt to update session title - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "UPDATE conversationSession SET title = 'Changed' WHERE id = ?", arguments: [sessionId])
        }
        
        // Attempt to delete session - SHOULD SUCCESS
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM conversationSession WHERE id = ?", arguments: [sessionId])
        }
        
        let fetched = try await persistence.fetchSession(id: sessionId)
        #expect(fetched == nil)
    }
}

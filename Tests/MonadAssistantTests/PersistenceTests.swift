import Foundation
import GRDB
import Testing

@testable import MonadAssistant

@Suite(.serialized)
@MainActor
struct PersistenceTests {
    private let persistence: PersistenceService

    init() async throws {
        // Use an in-memory database for testing
        let queue = try DatabaseQueue()
        // Register migrations
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
    }

    @Test("Test creating a conversation session")
    func sessionCreation() async throws {
        let session = ConversationSession(title: "Test Session")
        try await persistence.saveSession(session)

        let fetched = try await persistence.fetchSession(id: session.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Session")
    }

    @Test("Test message persistence within a session")
    func messagePersistence() async throws {
        let session = ConversationSession(title: "Test Session")
        try await persistence.saveSession(session)

        let message = ConversationMessage(
            sessionId: session.id,
            role: .user,
            content: "Hello World"
        )
        try await persistence.saveMessage(message)

        let messages = try await persistence.fetchMessages(for: session.id)
        #expect(messages.count == 1)
        #expect(messages.first?.content == "Hello World")
    }

    @Test("Test cascading deletes: Deleting a session removes its messages")
    func cascadingDeletes() async throws {
        let session = ConversationSession(title: "Test Session")
        try await persistence.saveSession(session)

        let message = ConversationMessage(sessionId: session.id, role: .user, content: "Delete me")
        try await persistence.saveMessage(message)

        try await persistence.deleteSession(id: session.id)

        let messages = try await persistence.fetchMessages(for: session.id)
        #expect(messages.isEmpty)
    }

    @Test("Test message ordering: Messages are chronological")
    func messageOrdering() async throws {
        let session = ConversationSession(title: "Test Session")
        try await persistence.saveSession(session)

        let m1 = ConversationMessage(
            sessionId: session.id, role: .user, content: "First",
            timestamp: Date().addingTimeInterval(-10))
        let m2 = ConversationMessage(
            sessionId: session.id, role: .assistant, content: "Second", timestamp: Date())

        try await persistence.saveMessage(m2)
        try await persistence.saveMessage(m1)

        let messages = try await persistence.fetchMessages(for: session.id)
        #expect(messages.count == 2)
        #expect(messages[0].content == "First")
        #expect(messages[1].content == "Second")
    }

    @Test("Test archiving and filtering sessions")
    func archiveSession() async throws {
        var session = ConversationSession(title: "Test Session")
        session.isArchived = false
        try await persistence.saveSession(session)

        session.isArchived = true
        try await persistence.saveSession(session)

        let archived = try await persistence.fetchAllSessions(includeArchived: true)
        #expect(archived.contains { $0.id == session.id && $0.isArchived })

        let active = try await persistence.fetchAllSessions(includeArchived: false)
        #expect(!active.contains { $0.id == session.id })
    }

    @Test("Test note persistence and search")
    func notePersistence() async throws {
        let note = Note(name: "Test Note", content: "Test Content")
        try await persistence.saveNote(note)

        let fetched = try await persistence.fetchNote(id: note.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Test Note")

        let searchResults = try await persistence.searchNotes(query: "Test")
        #expect(searchResults.count >= 1)  // Default notes might also match
        #expect(searchResults.contains { $0.name == "Test Note" })
    }

    @Test("Test readonly note protection: Cannot delete system notes")
    func readonlyNoteProtection() async throws {
        let notes = try await persistence.fetchAllNotes()
        let systemNote = notes.first { $0.isReadonly }

        #expect(systemNote != nil, "System note should exist by default")

        if let id = systemNote?.id {
            await #expect(throws: NoteError.noteIsReadonly) {
                try await persistence.deleteNote(id: id)
            }
        }
    }

    @Test("Test database reset: Wipes data but restores defaults")
    func databaseReset() async throws {
        // Add some custom data
        try await persistence.saveSession(ConversationSession(title: "To Wipe"))
        try await persistence.saveNote(Note(name: "Custom Note", content: "To Wipe"))

        try await persistence.resetDatabase()

        let sessions = try await persistence.fetchAllSessions(includeArchived: true)
        #expect(sessions.isEmpty)

        let notes = try await persistence.fetchAllNotes()
        #expect(!notes.contains { $0.name == "Custom Note" })
        #expect(notes.contains { $0.name == "System" })  // Default restored
    }

    @Test("Test advanced search with partial matches")
    func advancedSearch() async throws {
        try await persistence.saveNote(Note(name: "Swift Programming", content: "Great language"))
        try await persistence.saveNote(Note(name: "Python Scripting", content: "Easy to use"))

        let swiftSearch = try await persistence.searchNotes(query: "Swift")
        #expect(swiftSearch.count == 1)
        #expect(swiftSearch.first?.name == "Swift Programming")

        let partialSearch = try await persistence.searchNotes(query: "ing")
        #expect(partialSearch.count >= 2)
    }

    @Test("Test memory persistence: Save, fetch, update")
    func memoryPersistence() async throws {
        // Save
        let memory = Memory(title: "Test Memory", content: "Initial content")
        try await persistence.saveMemory(memory)

        // Fetch
        guard let fetched = try await persistence.fetchMemory(id: memory.id) else {
            Issue.record("Memory not found after save")
            return
        }
        #expect(fetched.title == "Test Memory")
        #expect(fetched.content == "Initial content")

        // Update
        var updated = fetched
        updated.content = "Updated content"
        try await persistence.saveMemory(updated)

        // Verify update
        let refetched = try await persistence.fetchMemory(id: memory.id)
        #expect(refetched?.content == "Updated content")
    }
}

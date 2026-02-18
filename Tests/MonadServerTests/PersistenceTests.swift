import MonadShared
import Foundation
import GRDB
import MonadCore
import Testing
import MonadServer

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

    @Test("Test message persistence with recalled memories")
    func messagePersistenceWithMemories() async throws {
        let session = ConversationSession(title: "Test Session")
        try await persistence.saveSession(session)

        let memories = [
            Memory(title: "Memory 1", content: "Content 1"),
            Memory(title: "Memory 2", content: "Content 2")
        ]
        let memoriesJson = String(data: try JSONEncoder().encode(memories), encoding: .utf8)!

        let message = ConversationMessage(
            sessionId: session.id,
            role: .user,
            content: "Message with memories",
            recalledMemories: memoriesJson
        )
        try await persistence.saveMessage(message)

        let fetchedMessages = try await persistence.fetchMessages(for: session.id)
        #expect(fetchedMessages.count == 1)

        let uiMessage = fetchedMessages[0].toMessage()
        #expect(uiMessage.recalledMemories?.count == 2)
        #expect(uiMessage.recalledMemories?[0].title == "Memory 1")
    }

    @Test("Test cascading deletes: Deleting an archived session is now blocked")
    func cascadingDeletes() async throws {
        var session = ConversationSession(title: "Test Session")
        session.isArchived = true
        try await persistence.saveSession(session)

        let message = ConversationMessage(sessionId: session.id, role: .user, content: "Delete me")
        try await persistence.saveMessage(message)

        // Attempting to delete an archived session should now throw due to the SQLite trigger
        await #expect(throws: Error.self) {
            try await persistence.deleteSession(id: session.id)
        }
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

    @Test("Test archiving sessions: Once archived, they are immutable")
    func archiveSession() async throws {
        var session = ConversationSession(title: "Test Session")
        session.isArchived = false
        try await persistence.saveSession(session)

        // Marking as archived should work (0 -> 1)
        session.isArchived = true
        try await persistence.saveSession(session)

        let archived = try await persistence.fetchAllSessions(includeArchived: true)
        #expect(archived.contains { $0.id == session.id && $0.isArchived })

        // Further modifications should fail
        session.title = "Changed Title"
        await #expect(throws: Error.self) {
            try await persistence.saveSession(session)
        }
    }

    @Test("Test database reset: Wipes only non-immutable data")
    func databaseReset() async throws {
        // Add some custom data
        try await persistence.saveSession(ConversationSession(title: "Archive to keep"))
        let memory = Memory(title: "Memory to wipe", content: "Should be gone")
        _ = try await persistence.saveMemory(memory, policy: .immediate)

        try await persistence.resetDatabase()

        let sessions = try await persistence.fetchAllSessions(includeArchived: true)
        #expect(!sessions.isEmpty, "Archives should be preserved")

        let allMemories = try await persistence.fetchAllMemories()
        #expect(allMemories.isEmpty, "Memories should be wiped")
    }

    @Test("Test memory persistence and retrieval")
    func memoryPersistence() async throws {
        let memory = Memory(
            title: "Test Memory", content: "This is a test memory", tags: ["test", "memory"])
        _ = try await persistence.saveMemory(memory, policy: .immediate)

        let fetched = try await persistence.fetchMemory(id: memory.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Memory")
        #expect(fetched?.content == "This is a test memory")
        #expect(fetched?.tagArray.contains("test") == true)
        #expect(fetched?.tagArray.contains("memory") == true)

        let allMemories = try await persistence.fetchAllMemories()
        #expect(allMemories.contains { $0.id == memory.id })
    }

    @Test("Test memory update (upsert)")
    func memoryUpdate() async throws {
        var memory = Memory(title: "Original Title", content: "Original Content")
        _ = try await persistence.saveMemory(memory, policy: .immediate)

        let fetchedOriginal = try await persistence.fetchMemory(id: memory.id)
        #expect(fetchedOriginal?.title == "Original Title")

        // Update
        memory.title = "Updated Title"
        memory.content = "Updated Content"
        _ = try await persistence.saveMemory(memory, policy: .immediate)

        let fetchedUpdated = try await persistence.fetchMemory(id: memory.id)
        #expect(fetchedUpdated?.title == "Updated Title")
        #expect(fetchedUpdated?.content == "Updated Content")

        // Ensure count is still 1
        let allMemories = try await persistence.fetchAllMemories()
        #expect(allMemories.count == 1)
    }

    @Test("Test semantic memory search")
    func semanticSearch() async throws {
        // Create memories with distinct vectors
        let m1 = Memory(title: "Apple", content: "A fruit", embedding: [1.0, 0.0, 0.0])
        let m2 = Memory(title: "Banana", content: "Another fruit", embedding: [0.0, 1.0, 0.0])

        _ = try await persistence.saveMemory(m1, policy: .immediate)
        _ = try await persistence.saveMemory(m2, policy: .immediate)

        // Search for something close to m1
        let results = try await persistence.searchMemories(embedding: [0.9, 0.1, 0.0], limit: 1, minSimilarity: 0.1)

        #expect(results.count == 1)
        #expect(results.first?.memory.title == "Apple")
        #expect(results.first?.similarity ?? 0 > 0.9)
    }

    @Test("Test search memories with empty database")
    func searchMemoriesEmpty() async throws {
        let results = try await persistence.searchMemories(embedding: [1.0, 0.0, 0.0], limit: 5, minSimilarity: 0.1)
        #expect(results.isEmpty)
    }
}

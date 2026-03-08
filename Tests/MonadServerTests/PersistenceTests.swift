import Foundation
import GRDB
import MonadCore
import MonadServer
import MonadShared
import Testing

@Suite(.serialized)
@MainActor
struct PersistenceTests {
    private let dbQueue: DatabaseQueue
    private let timelineStore: TimelineRepository
    private let messageStore: MessageRepository
    private let memoryStore: MemoryRepository

    init() async throws {
        // Use an in-memory database for testing
        let queue = try DatabaseQueue()
        // Register migrations
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        dbQueue = queue
        timelineStore = TimelineRepository(dbQueue: queue)
        messageStore = MessageRepository(dbQueue: queue)
        memoryStore = MemoryRepository(dbQueue: queue)
    }

    @Test("Test creating a conversation session")
    func sessionCreation() async throws {
        let session = Timeline(title: "Test Session")
        try await timelineStore.saveTimeline(session)

        let fetched = try await timelineStore.fetchTimeline(id: session.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Session")
    }

    @Test("Test message persistence within a session")
    func messagePersistence() async throws {
        let session = Timeline(title: "Test Session")
        try await timelineStore.saveTimeline(session)

        let message = ConversationMessage(
            timelineId: session.id,
            role: .user,
            content: "Hello World"
        )
        try await messageStore.saveMessage(message)

        let messages = try await messageStore.fetchMessages(for: session.id)
        #expect(messages.count == 1)
        #expect(messages.first?.content == "Hello World")
    }

    @Test("Test message persistence with recalled memories")
    func messagePersistenceWithMemories() async throws {
        let session = Timeline(title: "Test Session")
        try await timelineStore.saveTimeline(session)

        let memories = [
            Memory(title: "Memory 1", content: "Content 1"),
            Memory(title: "Memory 2", content: "Content 2"),
        ]
        let memoriesJson = try #require(String(data: JSONEncoder().encode(memories), encoding: .utf8))

        let message = ConversationMessage(
            timelineId: session.id,
            role: .user,
            content: "Message with memories",
            recalledMemories: memoriesJson
        )
        try await messageStore.saveMessage(message)

        let fetchedMessages = try await messageStore.fetchMessages(for: session.id)
        #expect(fetchedMessages.count == 1)

        let uiMessage = fetchedMessages[0].toMessage()
        #expect(uiMessage.recalledMemories?.count == 2)
        #expect(uiMessage.recalledMemories?[0].title == "Memory 1")
    }

    @Test("Test cascading deletes: Deleting an archived session is now blocked")
    func cascadingDeletes() async throws {
        var session = Timeline(title: "Test Session")
        session.isArchived = true
        try await timelineStore.saveTimeline(session)

        let message = ConversationMessage(timelineId: session.id, role: .user, content: "Delete me")
        try await messageStore.saveMessage(message)

        // Attempting to delete an archived session should now throw due to the SQLite trigger
        await #expect(throws: Error.self) {
            try await timelineStore.deleteTimeline(id: session.id)
        }
    }

    @Test("Test message ordering: Messages are chronological")
    func messageOrdering() async throws {
        let session = Timeline(title: "Test Session")
        try await timelineStore.saveTimeline(session)

        let m1 = ConversationMessage(
            timelineId: session.id, role: .user, content: "First",
            timestamp: Date().addingTimeInterval(-10)
        )
        let m2 = ConversationMessage(
            timelineId: session.id, role: .assistant, content: "Second", timestamp: Date()
        )

        try await messageStore.saveMessage(m2)
        try await messageStore.saveMessage(m1)

        let messages = try await messageStore.fetchMessages(for: session.id)
        #expect(messages.count == 2)
        #expect(messages[0].content == "First")
        #expect(messages[1].content == "Second")
    }

    @Test("Test archiving sessions: Once archived, they are immutable")
    func archiveSession() async throws {
        var session = Timeline(title: "Test Session")
        session.isArchived = false
        try await timelineStore.saveTimeline(session)

        // Marking as archived should work (0 -> 1)
        session.isArchived = true
        try await timelineStore.saveTimeline(session)

        let archived = try await timelineStore.fetchAllTimelines(includeArchived: true)
        #expect(archived.contains { $0.id == session.id && $0.isArchived })

        // Further modifications should fail
        session.title = "Changed Title"
        await #expect(throws: Error.self) {
            try await timelineStore.saveTimeline(session)
        }
    }

    @Test("Test database reset: Wipes only non-immutable data")
    func databaseReset() async throws {
        // Create an archived timeline (immutable, should be preserved after reset)
        var archivedSession = Timeline(title: "Archive to keep")
        archivedSession.isArchived = true
        try await timelineStore.saveTimeline(archivedSession)

        // Create a memory (mutable, should be wiped)
        let memory = Memory(title: "Memory to wipe", content: "Should be gone")
        _ = try await memoryStore.saveMemory(memory, policy: .immediate)

        // Reset the database via DatabaseManager
        let databaseManager = DatabaseManager(dbQueue: dbQueue)
        try await databaseManager.resetDatabase()

        let sessions = try await timelineStore.fetchAllTimelines(includeArchived: true)
        #expect(!sessions.isEmpty, "Archives should be preserved")

        let allMemories = try await memoryStore.fetchAllMemories()
        #expect(allMemories.isEmpty, "Memories should be wiped")
    }

    @Test("Test memory persistence and retrieval")
    func memoryPersistence() async throws {
        let memory = Memory(
            title: "Test Memory", content: "This is a test memory", tags: ["test", "memory"]
        )
        _ = try await memoryStore.saveMemory(memory, policy: .immediate)

        let fetched = try await memoryStore.fetchMemory(id: memory.id)
        #expect(fetched != nil)
        #expect(fetched?.title == "Test Memory")
        #expect(fetched?.content == "This is a test memory")
        #expect(fetched?.tagArray.contains("test") == true)
        #expect(fetched?.tagArray.contains("memory") == true)

        let allMemories = try await memoryStore.fetchAllMemories()
        #expect(allMemories.contains { $0.id == memory.id })
    }

    @Test("Test memory update (upsert)")
    func memoryUpdate() async throws {
        var memory = Memory(title: "Original Title", content: "Original Content")
        _ = try await memoryStore.saveMemory(memory, policy: .immediate)

        let fetchedOriginal = try await memoryStore.fetchMemory(id: memory.id)
        #expect(fetchedOriginal?.title == "Original Title")

        // Update
        memory.title = "Updated Title"
        memory.content = "Updated Content"
        _ = try await memoryStore.saveMemory(memory, policy: .immediate)

        let fetchedUpdated = try await memoryStore.fetchMemory(id: memory.id)
        #expect(fetchedUpdated?.title == "Updated Title")
        #expect(fetchedUpdated?.content == "Updated Content")

        // Ensure count is still 1
        let allMemories = try await memoryStore.fetchAllMemories()
        #expect(allMemories.count == 1)
    }

    @Test("Test semantic memory search")
    func semanticSearch() async throws {
        // Create memories with distinct vectors
        let m1 = Memory(title: "Apple", content: "A fruit", embedding: [1.0, 0.0, 0.0])
        let m2 = Memory(title: "Banana", content: "Another fruit", embedding: [0.0, 1.0, 0.0])

        _ = try await memoryStore.saveMemory(m1, policy: .immediate)
        _ = try await memoryStore.saveMemory(m2, policy: .immediate)

        // Search for something close to m1
        let results = try await memoryStore.searchMemories(embedding: [0.9, 0.1, 0.0], limit: 1, minSimilarity: 0.1)

        #expect(results.count == 1)
        #expect(results.first?.memory.title == "Apple")
        #expect(results.first?.similarity ?? 0 > 0.9)
    }

    @Test("Test search memories with empty database")
    func searchMemoriesEmpty() async throws {
        let results = try await memoryStore.searchMemories(embedding: [1.0, 0.0, 0.0], limit: 5, minSimilarity: 0.1)
        #expect(results.isEmpty)
    }
}

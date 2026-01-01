import Foundation
import GRDB
import Shared
import Testing

@testable import MonadAssistant

@Suite(.serialized)
@MainActor
struct CreateMemoryToolTests {
    private let persistence: PersistenceService
    private let persistenceManager: PersistenceManager
    private let tool: CreateMemoryTool

    init() async throws {
        // Use an in-memory database for testing
        let queue = try DatabaseQueue()
        // Register migrations
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        persistenceManager = PersistenceManager(persistence: persistence)
        tool = CreateMemoryTool(persistenceManager: persistenceManager)
    }

    @Test("Test creating a memory successfully")
    func createMemorySuccess() async throws {
        let parameters: [String: Any] = [
            "title": "My Memory",
            "content": "This is important content to remember.",
            "tags": ["tag1", "tag2"]
        ]

        let result = try await tool.execute(parameters: parameters)

        // Verify the result is success
        switch result {
        case .success(let message):
            #expect(message.contains("My Memory"))
            #expect(message.contains("created successfully"))
        case .failure(let error):
            Issue.record("Expected success but got failure: \(error)")
        }

        // Verify the memory was saved in the database
        let memories = try await persistenceManager.fetchAllMemories()
        #expect(memories.count == 1)

        let memory = memories.first
        #expect(memory?.title == "My Memory")
        #expect(memory?.content == "This is important content to remember.")
        #expect(memory?.tagArray.contains("tag1") == true)
        #expect(memory?.tagArray.contains("tag2") == true)
    }

    @Test("Test creating a memory without tags")
    func createMemoryWithoutTags() async throws {
        let parameters: [String: Any] = [
            "title": "No Tags Memory",
            "content": "Content without tags."
        ]

        let result = try await tool.execute(parameters: parameters)

        switch result {
        case .success:
            break // Expected
        case .failure(let error):
            Issue.record("Expected success but got failure: \(error)")
        }

        let memories = try await persistenceManager.fetchAllMemories()
        let memory = memories.first { $0.title == "No Tags Memory" }

        #expect(memory != nil)
        #expect(memory?.tagArray.isEmpty == true)
    }

    @Test("Test missing required parameters")
    func missingParameters() async throws {
        let parameters: [String: Any] = [
            "title": "Only Title"
        ]

        let result = try await tool.execute(parameters: parameters)

        switch result {
        case .failure(let error):
            #expect(error.contains("Missing required parameters"))
        case .success:
            Issue.record("Expected failure but got success")
        }

        let memories = try await persistenceManager.fetchAllMemories()
        #expect(memories.isEmpty)
    }
}

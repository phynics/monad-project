import Foundation
import GRDB
import MonadCore
import Testing

@Suite(.serialized)
@MainActor
struct CreateMemoryToolTests {
    private let persistence: PersistenceService
    private let tool: CreateMemoryTool

    init() async throws {
        // Use an in-memory database for testing
        let queue = try DatabaseQueue()
        // Register migrations
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        tool = CreateMemoryTool(persistenceService: persistence, embeddingService: LocalEmbeddingService())
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
        #expect(result.success)
        #expect(result.output.contains("My Memory"))
        #expect(result.output.contains("created successfully"))

        // Verify the memory was saved in the database
        let memories = try await persistence.fetchAllMemories()
        #expect(memories.count == 1)

        let memory = memories.first
        #expect(memory?.title == "My Memory")
        #expect(memory?.content == "This is important content to remember.")
        #expect(memory?.tagArray.contains("tag1") == true)
        #expect(memory?.tagArray.contains("tag2") == true)
        
        // Verify embedding was generated
        #expect(memory?.embeddingVector.count == 512)
    }

    @Test("Test creating a memory without tags")
    func createMemoryWithoutTags() async throws {
        let parameters: [String: Any] = [
            "title": "Natural Language Processing",
            "content": "Computational linguistics is an interdisciplinary field."
        ]

        let result = try await tool.execute(parameters: parameters)

        #expect(result.success)

        let memories = try await persistence.fetchAllMemories()
        let memory = memories.first { $0.title == "Natural Language Processing" }

        #expect(memory != nil)
        // Verify automatic keyword extraction occurred (should find linguistics, field, etc)
        #expect(memory?.tagArray.isEmpty == false)
        #expect((memory?.tagArray.count ?? 0) > 0)
    }

    @Test("Test missing required parameters")
    func missingParameters() async throws {
        let parameters: [String: Any] = [
            "title": "Only Title"
        ]

        let result = try await tool.execute(parameters: parameters)

        #expect(!result.success)
        #expect(result.error?.contains("Missing required parameters") == true)

        let memories = try await persistence.fetchAllMemories()
        #expect(memories.isEmpty)
    }
}

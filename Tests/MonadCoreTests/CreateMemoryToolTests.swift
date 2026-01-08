import Foundation
import GRDB
import MonadCore
import Testing

@testable import MonadCore

@Suite(.serialized)
@MainActor
struct CreateMemoryToolTests {
    private let persistence: PersistenceService
    private let tool: CreateMemoryTool
    private let mockEmbeddingService: MockEmbeddingService

    init() async throws {
        // Use an in-memory database for testing
        let queue = try DatabaseQueue()
        // Register migrations
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        mockEmbeddingService = MockEmbeddingService()
        tool = CreateMemoryTool(persistenceService: persistence, embeddingService: mockEmbeddingService)
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
        
        // Verify embedding was generated (Mock returns 3 dimensions)
        #expect(memory?.embeddingVector.count == 3)
        #expect(memory?.embeddingVector == [0.1, 0.2, 0.3])
    }

    #if canImport(NaturalLanguage)
    @Test("Test creating a memory without tags (Auto-tagging)")
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
    #endif

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

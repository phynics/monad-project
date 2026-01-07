import XCTest
@testable import MonadCore
import GRDB

final class ContextManagerTests: XCTestCase {
    var persistence: PersistenceService!
    var contextManager: ContextManager!
    var mockEmbedding: MockEmbeddingService!
    
    override func setUp() async throws {
        let queue = try DatabaseQueue()
        
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        
        persistence = PersistenceService(dbQueue: queue)
        try await queue.write { db in
            try DatabaseSchema.createDefaultNotes(in: db)
        }
        
        mockEmbedding = MockEmbeddingService()
        contextManager = ContextManager(persistenceService: persistence, embeddingService: mockEmbedding)
    }
    
    func testGatherContextUsesHistoryForTagsButQueryForEmbedding() async throws {
        // Setup a memory to find
        let memory = Memory(
            title: "Project Alpha",
            content: "Details about Alpha",
            tags: ["alpha", "secret"],
            embedding: [0.1, 0.2, 0.3]
        )
        try await persistence.saveMemory(memory)
        
        // Mock tag generator that returns tags based on full context
        let tagGenerator: @Sendable (String) async throws -> [String] = { text in
            if text.contains("Previous") && text.contains("Current") {
                return ["alpha"]
            }
            return []
        }
        
        mockEmbedding.mockEmbedding = [0.1, 0.2, 0.3]
        
        let history = [
            Message(content: "Previous message", role: .user)
        ]
        
        let context = try await contextManager.gatherContext(
            for: "Current query",
            history: history,
            tagGenerator: tagGenerator
        )
        
        // Check augmented query (used for tags)
        XCTAssertTrue(context.augmentedQuery?.contains("Previous message") == true)
        XCTAssertTrue(context.augmentedQuery?.contains("Current query") == true)
        
        // Check results
        XCTAssertFalse(context.memories.isEmpty)
        XCTAssertEqual(context.memories.first?.memory.id, memory.id)
        
        // Verify embedding was called with just the query, not the full history
        // (Assuming MockEmbeddingService tracks last input)
        XCTAssertEqual(mockEmbedding.lastInput, "Current query")
    }
}

final class MockEmbeddingService: EmbeddingService, @unchecked Sendable {
    var mockEmbedding: [Double] = [0.1, 0.2, 0.3]
    var lastInput: String?
    
    func generateEmbedding(for text: String) async throws -> [Double] {
        lastInput = text
        return mockEmbedding
    }
    
    func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
        return texts.map { _ in mockEmbedding }
    }
}

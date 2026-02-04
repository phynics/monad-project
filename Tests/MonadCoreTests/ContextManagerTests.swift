import XCTest

@testable import MonadCore

final class ContextManagerTests: XCTestCase {
    var mockPersistence: MockPersistenceService!
    var mockEmbedding: MockEmbeddingService!
    var contextManager: ContextManager!

    override func setUp() async throws {
        mockPersistence = MockPersistenceService()
        mockEmbedding = MockEmbeddingService()
        contextManager = ContextManager(
            persistenceService: mockPersistence, embeddingService: mockEmbedding)
    }

    func testGatherContextSemanticRetrieval() async throws {
        // Setup
        let expectedMemory = Memory(
            title: "SwiftUI Guide",
            content: "SwiftUI is declarative.",
            tags: ["swiftui"],
            embedding: [0.1, 0.2, 0.3]
        )
        mockPersistence.memories = [expectedMemory]
        mockPersistence.searchResults = [(expectedMemory, 0.9)]

        // Execute
        let context = try await contextManager.gatherContext(for: "How to use SwiftUI?")

        // Verify
        XCTAssertEqual(context.memories.count, 1)
        XCTAssertEqual(context.memories.first?.memory.id, expectedMemory.id)
        XCTAssertEqual(context.memories.first?.similarity ?? 0, 0.9, accuracy: 0.001)
        XCTAssertEqual(mockEmbedding.lastInput, "How to use SwiftUI?")
    }

    func testGatherContextUsesHistoryForTagsButQueryForEmbedding() async throws {
        // Setup
        let memory = Memory(
            title: "Project Alpha",
            content: "Details about Alpha",
            tags: ["alpha"],
            embedding: [0.1, 0.2, 0.3]
        )
        mockPersistence.memories = [memory]
        mockPersistence.searchResults = [(memory, 0.85)]

        let tagGenerator: @Sendable (String) async throws -> [String] = { text in
            if text.contains("Previous") {
                return ["alpha"]
            }
            return []
        }

        let history = [Message(content: "Previous message", role: .user)]

        // Execute
        let context = try await contextManager.gatherContext(
            for: "Current query",
            history: history,
            tagGenerator: tagGenerator
        )

        // Verify
        XCTAssertTrue(context.augmentedQuery?.contains("Previous message") == true)
        XCTAssertEqual(mockEmbedding.lastInput, "Current query")  // Embedding only uses query
    }

    func testRankingLogicWithTagBoost() async throws {
        // Setup
        let memory1 = Memory(
            title: "Tag Match", content: "Matches tag", tags: ["swift"], embedding: [0.1])
        let memory2 = Memory(
            title: "Semantic Match", content: "Matches vector", tags: [], embedding: [0.9])

        // Mock persistence behavior:
        // searchMemories(matchingAnyTag:) returns memory1
        // searchMemories(embedding:) returns memory2

        // We need to subclass or customize MockPersistenceService to return specific results for specific calls
        // Or simpler: MockPersistenceService just returns what's in its arrays.
        // But searchMemories(matchingAnyTag) filters 'memories' array in our mock.
        // searchMemories(embedding) returns 'searchResults'.

        mockPersistence.memories = [memory1]  // Will be found by tag search
        mockPersistence.searchResults = [(memory2, 0.8)]  // Will be found by vector search

        let tagGenerator: @Sendable (String) async throws -> [String] = { _ in ["swift"] }

        // Execute
        let context = try await contextManager.gatherContext(
            for: "swift query",
            tagGenerator: tagGenerator
        )

        // Verify
        // ContextManager ranks by similarity. Tag matches get a +2.0 boost.
        // Memory1 (Tag Match): Base sim (computed by VectorMath on mockEmbedding vs memory1.embedding) + 2.0
        // Memory2 (Semantic Match): 0.8

        // MockEmbedding default is [0.1, 0.2, 0.3]. Memory1 is [0.1]. Dimensions mismatch?
        // Let's ensure embeddings align for VectorMath if it runs.
        // Memory1 (Tag Match): Base sim 0.0 (dimension mismatch) + 0.5 boost = 0.5
        // Memory2 (Semantic Match): 0.8

        XCTAssertEqual(context.memories.count, 2)

        // Memory2 should be first because 0.8 > 0.5 (Semantic wins with reduced boost)
        XCTAssertEqual(context.memories.first?.memory.title, "Semantic Match")

        // Memory1 should be second
        let tagMatch = context.memories.last
        XCTAssertEqual(tagMatch?.memory.title, "Tag Match")
        // Verify boost was applied (0.0 + 0.5)
        XCTAssertEqual(tagMatch?.similarity ?? 0, 0.5, accuracy: 0.1)
    }

    func testAdaptiveLearning() async throws {
        // Setup
        let memoryId = UUID()
        let initialVector = [1.0, 0.0, 0.0]  // X-axis
        let memory = Memory(
            id: memoryId,
            title: "Learning Memory",
            content: "Some content",
            tags: [],
            embedding: initialVector
        )
        mockPersistence.memories = [memory]

        // Query vector is pointing towards Y-axis
        let queryVector = [0.0, 1.0, 0.0]

        // Positive feedback: memory should move towards query vector
        let evaluations = [memoryId.uuidString: 1.0]

        // Execute
        try await contextManager.adjustEmbeddings(
            evaluations: evaluations, queryVectors: [queryVector])

        // Verify update was called
        // We need to see if updateMemoryEmbedding was called on the mock
        // Since our MockPersistenceService updates its 'memories' array:
        let updatedMemory = try await mockPersistence.fetchMemory(id: memoryId)
        let updatedVector = updatedMemory?.embeddingVector ?? []

        XCTAssertFalse(updatedVector.isEmpty)
        XCTAssertNotEqual(updatedVector, initialVector)

        // In this simple case, a positive shift from [1,0,0] towards [0,1,0]
        // should increase the Y component and decrease the X component.
        XCTAssertGreaterThan(updatedVector[1], initialVector[1])
        XCTAssertLessThan(updatedVector[0], initialVector[0])
    }
    
    func testFilesystemNotesRetrieval() async throws {
        // 1. Setup workspace with a note file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let notesDir = tempURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let noteContent = """
        _Description: FS Note Description_
        
        Content from filesystem.
        """
        try noteContent.write(to: notesDir.appendingPathComponent("FSNote.md"), atomically: true, encoding: .utf8)
        
        // 2. Initialize ContextManager with workspaceRoot
        let manager = ContextManager(
            persistenceService: mockPersistence,
            embeddingService: mockEmbedding,
            workspaceRoot: tempURL
        )
        
        // 3. Execute
        let context = try await manager.gatherContext(for: "some query")
        
        // 4. Verify
        XCTAssertEqual(context.notes.count, 1)
        let note = context.notes.first
        XCTAssertEqual(note?.name, "FSNote")
        XCTAssertEqual(note?.description, "FS Note Description")
        XCTAssertEqual(note?.content, "Content from filesystem.")
    }
}

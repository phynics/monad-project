import Testing
import Foundation
@testable import MonadCore

@Suite("Context Manager Tests")
struct ContextManagerTests {
    
    @Test("Gather Context: Semantic Retrieval")
    func testGatherContextSemanticRetrieval() async throws {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()
        let contextManager = ContextManager(
            persistenceService: mockPersistence, 
            embeddingService: mockEmbedding, 
            workspace: nil
        )

        let expectedMemory = Memory.fixture(
            title: "SwiftUI Guide",
            content: "SwiftUI is declarative.",
            tags: ["swiftui"]
        )
        mockPersistence.memories = [expectedMemory]
        mockPersistence.searchResults = [(expectedMemory, 0.9)]

        let stream = await contextManager.gatherContext(for: "How to use SwiftUI?")
        let events = try await stream.collect()
        
        let context = events.compactMap { if case .complete(let data) = $0 { return data } else { return nil } }.first
        
        guard let context = context else {
            Issue.record("Context gathering failed to produce result")
            return
        }

        #expect(context.memories.count == 1)
        #expect(context.memories.first?.memory.id == expectedMemory.id)
        #expect(context.memories.first?.similarity ?? 0 == 0.9)
        #expect(mockEmbedding.lastInput == "How to use SwiftUI?")
    }

    @Test("Gather Context: Uses History for Tags but Query for Embedding")
    func testGatherContextUsesHistoryForTagsButQueryForEmbedding() async throws {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()
        let contextManager = ContextManager(
            persistenceService: mockPersistence, 
            embeddingService: mockEmbedding, 
            workspace: nil
        )

        let memory = Memory.fixture(title: "Project Alpha", tags: "alpha")
        mockPersistence.memories = [memory]
        mockPersistence.searchResults = [(memory, 0.85)]

        let tagGenerator: @Sendable (String) async throws -> [String] = { text in
            if text.contains("Previous") { return ["alpha"] }
            return []
        }

        let history = [Message.fixture(content: "Previous message")]

        let stream = await contextManager.gatherContext(
            for: "Current query",
            history: history,
            tagGenerator: tagGenerator
        )
        let events = try await stream.collect()
        let context = events.compactMap { if case .complete(let data) = $0 { return data } else { return nil } }.first

        guard let context = context else {
            Issue.record("Context gathering failed to produce result")
            return
        }

        #expect(context.augmentedQuery?.contains("Previous message") == true)
        #expect(mockEmbedding.lastInput == "Current query")
    }

    @Test("Ranking Logic with Tag Boost")
    func testRankingLogicWithTagBoost() async throws {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()
        let contextManager = ContextManager(
            persistenceService: mockPersistence, 
            embeddingService: mockEmbedding, 
            workspace: nil
        )

        let memory1 = Memory.fixture(title: "Tag Match", tags: "swift")
        let memory2 = Memory.fixture(title: "Semantic Match")

        mockPersistence.memories = [memory1]
        mockPersistence.searchResults = [(memory2, 0.8)]

        let tagGenerator: @Sendable (String) async throws -> [String] = { _ in ["swift"] }

        let stream = await contextManager.gatherContext(
            for: "swift query",
            tagGenerator: tagGenerator
        )
        let events = try await stream.collect()
        let context = events.compactMap { if case .complete(let data) = $0 { return data } else { return nil } }.first

        guard let context = context else {
            Issue.record("Context gathering failed to produce result")
            return
        }

        #expect(context.memories.count == 2)
        #expect(context.memories.first?.memory.title == "Semantic Match")
        
        let tagMatch = context.memories.last
        #expect(tagMatch?.memory.title == "Tag Match")
        #expect(tagMatch?.similarity ?? 0 == 0.5) // 0.0 base + 0.5 boost
    }

    @Test("Filesystem Notes Retrieval")
    func testFilesystemNotesRetrieval() async throws {
        let mockPersistence = MockPersistenceService()
        let mockEmbedding = MockEmbeddingService()
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let notesDir = tempURL.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let noteContent = """
        _Description: FS Note Description_

        Content from filesystem.
        """
        try noteContent.write(to: notesDir.appendingPathComponent("FSNote.md"), atomically: true, encoding: .utf8)

        let ref = WorkspaceReference.fixture(
            uri: WorkspaceURI(host: "monad-server", path: tempURL.path),
            rootPath: tempURL.path
        )
        let workspace = try MockLocalWorkspace(reference: ref)

        let manager = ContextManager(
            persistenceService: mockPersistence,
            embeddingService: mockEmbedding,
            workspace: workspace
        )

        let stream = await manager.gatherContext(for: "some query")
        let events = try await stream.collect()
        let context = events.compactMap { if case .complete(let data) = $0 { return data } else { return nil } }.first

        guard let context = context else {
            Issue.record("Context gathering failed to produce result")
            return
        }

        #expect(context.notes.count == 1)
        let note = context.notes.first
        #expect(note?.name == "FSNote")
        #expect(note?.source == "Notes/FSNote.md")
        #expect(note?.content == noteContent)
    }
}
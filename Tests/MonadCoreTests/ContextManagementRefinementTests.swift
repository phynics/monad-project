import XCTest
@testable import MonadCore

final class ContextManagementRefinementTests: XCTestCase {
    var mockPersistence: MockPersistenceService!
    var mockEmbedding: MockEmbeddingService!
    var mockLLMService: MockLLMService!
    var contextManager: ContextManager!
    
    @MainActor
    override func setUp() async throws {
        mockPersistence = MockPersistenceService()
        mockEmbedding = MockEmbeddingService()
        mockLLMService = MockLLMService()
        contextManager = ContextManager(persistenceService: mockPersistence, embeddingService: mockEmbedding)
    }
    
    @MainActor
    func testAlwaysAppendNotesFiltering() async throws {
        // Setup multiple "Always Append" notes
        let relevantNote = Note(
            id: UUID(),
            name: "SwiftUI Tips",
            content: "Always use declarative syntax.",
            alwaysAppend: true,
            tags: ["swiftui"]
        )
        let irrelevantNote = Note(
            id: UUID(),
            name: "Cooking Recipe",
            content: "How to make a cake.",
            alwaysAppend: true,
            tags: ["cooking"]
        )
        
        mockPersistence.notes = [relevantNote, irrelevantNote]
        
        // Execute context gathering for a SwiftUI query
        let context = try await contextManager.gatherContext(for: "How to build SwiftUI views?")
        
        // Verify only the relevant "Always Append" note is included
        // This is EXPECTED TO FAIL initially because current implementation returns ALL always-append notes.
        XCTAssertEqual(context.notes.count, 1, "Should only include relevant always-append notes")
        XCTAssertEqual(context.notes.first?.id, relevantNote.id)
    }
    
    @MainActor
    func testAlwaysAppendNotesLimiting() async throws {
        // Setup many relevant always-append notes
        var notes: [Note] = []
        for i in 1...10 {
            notes.append(Note(
                id: UUID(),
                name: "Note \(i)",
                content: "Content \(i) about SwiftUI",
                alwaysAppend: true,
                tags: ["swiftui"]
            ))
        }
        mockPersistence.notes = notes
        
        // Execute
        let context = try await contextManager.gatherContext(for: "SwiftUI")
        
        // Verify it doesn't include all 10
        // Let's say we want a limit of 3 for always-append notes to avoid clutter
        XCTAssertLessThanOrEqual(context.notes.count, 3, "Should limit the number of always-append notes")
    }
    
    @MainActor
    func testExtremeHistoryCompression() async throws {
        let compressor = ContextCompressor(llmService: mockLLMService)
        
        // Create 100 messages
        let messages = (0..<100).map { i in
            Message(content: "Message \(i)", role: .user)
        }
        
        // Execute compression
        let compressed = try await compressor.compress(messages: messages)
        
        // With 100 messages:
        // - 10 recent are kept raw.
        // - 90 older are chunked by 10 -> 9 chunks.
        // - Each chunk becomes a summary.
        // Total expected: 9 + 10 = 19 messages.
        XCTAssertEqual(compressed.count, 19, "Should compress 100 messages into 19 (9 summaries + 10 raw)")
        
        // Verify the first 9 are summaries
        for i in 0..<9 {
            XCTAssertTrue(compressed[i].isSummary)
            XCTAssertEqual(compressed[i].role, .summary)
        }
        
        // Verify the last 10 are the original recent messages
        for i in 0..<10 {
            XCTAssertEqual(compressed[9 + i].content, "Message \(90 + i)")
        }
    }
    
    @MainActor
    func testSmartChunkingAvoidsBreakingToolSequences() async throws {
        let compressor = ContextCompressor(llmService: mockLLMService)
        
        // Create a history with a tool sequence at the boundary of chunk size (10)
        var messages: [Message] = []
        for i in 0..<8 {
            messages.append(Message(content: "User \(i)", role: .user))
        }
        
        // Message 8 & 9 are a tool call and result
        let toolCall = ToolCall(name: "read_file", arguments: ["path": AnyCodable("test.txt")])
        messages.append(Message(content: "", role: .assistant, toolCalls: [toolCall])) // Index 8
        messages.append(Message(content: "File content", role: .tool)) // Index 9
        
        // Add 10 more messages to force compression of the first 10
        for i in 0..<10 {
            messages.append(Message(content: "Recent \(i)", role: .user))
        }
        
        // Execute compression
        _ = try await compressor.compress(messages: messages)
        
        // Current logic: 10 messages raw at the end. 
        // 10 older messages [0...9] are chunked.
        // Default topicGroupSize is 10. 
        // So [0...9] would be one chunk.
        
        // If I change topicGroupSize or add more messages to make it 11 older messages...
        // Let's add one more message at the beginning.
        messages.insert(Message(content: "Initial", role: .user), at: 0)
        // Now older messages are [0...10] -> 11 messages.
        // Chunk 1: [0...9]
        // Chunk 2: [10]
        // If index 10 was a tool result but index 9 was the call, they'd be split.
        
        // Execute compression
        mockLLMService.nextResponse = "MOCK SUMMARY"
        let compressed2 = try await compressor.compress(messages: messages)
        // With 11 older messages, if it avoids breaking the sequence, it should group all 11 into one chunk.
        // 1 summary + 10 recent = 11 messages.
        XCTAssertEqual(compressed2.count, 11, "Should group all 11 older messages into one summary to avoid breaking tool sequence")
        
        XCTAssertEqual(compressed2[0].content, "MOCK SUMMARY")
    }
}

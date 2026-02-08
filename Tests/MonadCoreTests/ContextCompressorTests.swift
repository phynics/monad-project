import XCTest
@testable import MonadCore

@MainActor
final class ContextCompressorTests: XCTestCase {
    var compressor: ContextCompressor!
    var llmService: LLMService!

    override func setUp() async throws {
        let embeddingService = LocalEmbeddingService()
        // Initialize with minimal dependencies. Storage will use standard defaults but we override config immediately.
        llmService = LLMService(embeddingService: embeddingService)

        // Manually set valid configuration
        var config = LLMConfiguration.openAI
        config.providers[.openAI]?.apiKey = "test-key"
        try await llmService.updateConfiguration(config)

        compressor = ContextCompressor()
    }

    func testCompressionBasics() async throws {
        // Create 25 messages.
        // Recent buffer is 10.
        // Older messages = 15.
        // Chunk size = 10.
        // So we expect:
        // - 1 Topic Summary (covering first 10 messages)
        // - 1 Topic Summary (covering next 5 messages - actually currentChunk isn't empty)
        // Let's check logic:
        // chunks = olderMessages.chunked(into: 10) OR smartChunk
        // smartChunk logic:
        // [0...9] -> Chunk 1 (10 items)
        // [10...14] -> Chunk 2 (5 items)
        // So we get 2 Topic Summaries.
        // + 10 Recent messages.

        let messages = (0..<25).map { i in
            Message(content: "Message \(i)", role: .user)
        }

        let compressed = try await compressor.compress(messages: messages, llmService: llmService)

        // Expected: 2 summaries + 10 recent = 12 messages.
        XCTAssertEqual(compressed.count, 12)
        XCTAssertEqual(compressed[0].role, .summary)
        XCTAssertEqual(compressed[0].summaryType, .topic)
        XCTAssertEqual(compressed[1].role, .summary)
        XCTAssertEqual(compressed[1].summaryType, .topic)
        XCTAssertEqual(compressed[2].role, .user) // First recent message (Message 15)
        XCTAssertEqual(compressed[2].content, "Message 15")
    }

    func testBroadSummaryTrigger() async throws {
        // Broad summary triggers if total tokens of summaries > 2000.

        var hugeSummaries: [Message] = []
        let hugeText = String(repeating: "word ", count: 1000) // ~1333 tokens

        // Create 3 huge summaries. Total ~4000 tokens > 2000 threshold.
        // We add a tool call to force them to be chunked separately by smartChunk
        let toolCall = ToolCall(
            name: "mark_topic_change",
            arguments: ["new_topic": AnyCodable("Topic")]
        )

        for i in 0..<3 {
            let msg = Message(
                content: hugeText + " \(i)",
                role: .summary,
                toolCalls: [toolCall],
                isSummary: true,
                summaryType: .topic
            )
            hugeSummaries.append(msg)
        }

        // Add recent messages
        let recent = (0..<10).map { Message(content: "Recent \($0)", role: .user) }
        let input = hugeSummaries + recent

        let output = try await compressor.compress(messages: input, llmService: llmService)

        // Expected: 1 Broad Summary + 10 recent = 11 messages.
        XCTAssertEqual(output.count, 11)
        XCTAssertEqual(output[0].role, .summary)
        XCTAssertEqual(output[0].summaryType, .broad)
        XCTAssertEqual(output[1].content, "Recent 0")
    }

    func testSmartChunkingWithTopicChange() async throws {
        var olderMessages: [Message] = []
        for i in 0..<15 {
            var msg = Message(content: "Msg \(i)", role: .assistant)
            if i == 5 || i == 12 {
                let toolCall = ToolCall(
                    name: "mark_topic_change",
                    arguments: ["new_topic": AnyCodable("Topic \(i)")]
                )
                msg = Message(content: "Msg \(i)", role: .assistant, toolCalls: [toolCall])
            }
            olderMessages.append(msg)
        }

        let recent = (0..<10).map { Message(content: "Recent \($0)", role: .user) }
        let input = olderMessages + recent

        let output = try await compressor.compress(messages: input, llmService: llmService)

        // Expected: 3 Topic Summaries + 10 recent = 13 messages.
        XCTAssertEqual(output.count, 13)
        XCTAssertEqual(output[0].summaryType, .topic)
        XCTAssertEqual(output[1].summaryType, .topic)
        XCTAssertEqual(output[2].summaryType, .topic)
    }
}

import Testing
import Foundation
@testable import MonadCore
import MonadShared

@Suite("Context Compressor Tests")
@MainActor
struct ContextCompressorTests {
    
    @Test("Compression Basics")
    func testCompressionBasics() async throws {
        let llmService = MockLLMService()
        let compressor = ContextCompressor()

        let messages = (0..<25).map { i in
            Message.fixture(content: "Message \(i)")
        }

        let compressed = try await compressor.compress(messages: messages, llmService: llmService)

        // Expected: 2 summaries + 10 recent = 12 messages.
        #expect(compressed.count == 12)
        #expect(compressed[0].role == .summary)
        #expect(compressed[0].summaryType == .topic)
        #expect(compressed[1].role == .summary)
        #expect(compressed[1].summaryType == .topic)
        #expect(compressed[2].role == .user)
        #expect(compressed[2].content == "Message 15")
    }

    @Test("Broad Summary Trigger")
    func testBroadSummaryTrigger() async throws {
        let llmService = MockLLMService()
        let compressor = ContextCompressor()

        var hugeSummaries: [Message] = []
        let hugeText = String(repeating: "word ", count: 1000)

        let toolCall = ToolCall(
            name: "mark_topic_change",
            arguments: ["new_topic": AnyCodable("Topic")]
        )

        for i in 0..<3 {
            let msg = Message.fixture(
                role: .summary,
                content: hugeText + " \(i)"
            )
            // summaryType is not in fixture, set it manually if possible or use a more specific fixture
            var summaryMsg = msg
            summaryMsg.isSummary = true
            summaryMsg.summaryType = .topic
            hugeSummaries.append(summaryMsg)
        }

        let recent = (0..<10).map { Message.fixture(content: "Recent \($0)") }
        let input = hugeSummaries + recent

        let output = try await compressor.compress(messages: input, llmService: llmService)

        #expect(output.count == 11)
        #expect(output[0].role == .summary)
        #expect(output[0].summaryType == .broad)
        #expect(output[1].content == "Recent 0")
    }

    @Test("Smart Chunking with Topic Change")
    func testSmartChunkingWithTopicChange() async throws {
        let llmService = MockLLMService()
        let compressor = ContextCompressor()

        var olderMessages: [Message] = []
        for i in 0..<15 {
            var msg = Message.fixture(role: .assistant, content: "Msg \(i)")
            if i == 5 || i == 12 {
                let toolCall = ToolCall(
                    name: "mark_topic_change",
                    arguments: ["new_topic": AnyCodable("Topic \(i)")]
                )
                msg = Message.fixture(role: .assistant, content: "Msg \(i)")
                var tcMsg = msg
                tcMsg.toolCalls = [toolCall]
                msg = tcMsg
            }
            olderMessages.append(msg)
        }

        let recent = (0..<10).map { Message.fixture(content: "Recent \($0)") }
        let input = olderMessages + recent

        let output = try await compressor.compress(messages: input, llmService: llmService)

        #expect(output.count == 13)
        #expect(output[0].summaryType == .topic)
        #expect(output[1].summaryType == .topic)
        #expect(output[2].summaryType == .topic)
    }
}
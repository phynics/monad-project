import XCTest
@testable import MonadCore

// Mock for LLMServiceProtocol
actor MockLLMService: LLMServiceProtocol {
    var isConfigured: Bool = true
    var configuration: LLMConfiguration = .openAI

    // Stub response
    var summaryResponse: String = "Summary content"

    func loadConfiguration() async {}
    func updateConfiguration(_ config: LLMConfiguration) async throws {}
    func clearConfiguration() async {}
    func restoreFromBackup() async throws {}
    func exportConfiguration() async throws -> Data { return Data() }
    func importConfiguration(from data: Data) async throws {}

    func sendMessage(_ content: String) async throws -> String {
        return summaryResponse
    }

    func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool) async throws -> String {
        return summaryResponse
    }

    func chatStreamWithContext(userQuery: String, contextNotes: [ContextFile], documents: [DocumentContext], memories: [Memory], chatHistory: [Message], tools: [any Tool], systemInstructions: String?, responseFormat: ChatQuery.ResponseFormat?, useFastModel: Bool) async -> (stream: AsyncThrowingStream<ChatStreamResult, Error>, rawPrompt: String, structuredContext: [String: String]) {
        fatalError("Not implemented")
    }

    func chatStream(messages: [ChatQuery.ChatCompletionMessageParam], tools: [ChatQuery.ChatCompletionToolParam]?, responseFormat: ChatQuery.ResponseFormat?) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        fatalError("Not implemented")
    }

    func buildPrompt(userQuery: String, contextNotes: [ContextFile], documents: [DocumentContext], memories: [Memory], chatHistory: [Message], tools: [any Tool], systemInstructions: String?) async -> (messages: [ChatQuery.ChatCompletionMessageParam], rawPrompt: String, structuredContext: [String : String]) {
        fatalError("Not implemented")
    }

    func generateTags(for text: String) async throws -> [String] { return [] }
    func generateTitle(for messages: [Message]) async throws -> String { return "Title" }
    func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws -> [String : Double] { return [:] }
    func fetchAvailableModels() async throws -> [String]? { return [] }

    var healthStatus: HealthStatus { get async { .ok } }
    var healthDetails: [String : String]? { get async { [:] } }
    func checkHealth() async -> HealthStatus { .ok }
}

@MainActor
final class RaptorCompressionTests: XCTestCase {
    var compressor: ContextCompressor!
    var mockLLM: MockLLMService!

    override func setUp() async throws {
        compressor = ContextCompressor()
        mockLLM = MockLLMService()
    }

    func testSummarizeToolInteractions() async {
        // Create a history with tool interactions older than buffer (buffer=10)
        // We need > 10 messages.

        var messages: [Message] = []

        // 0-4: Simple chat
        for i in 0..<5 {
            messages.append(Message(content: "Msg \(i)", role: i % 2 == 0 ? .user : .assistant))
        }

        // 5: Assistant Tool Call
        let toolCall = ToolCall(name: "test_tool", arguments: [:])
        let msg5 = Message(content: "Calling tool", role: .assistant, toolCalls: [toolCall])
        messages.append(msg5)

        // 6: Tool Result
        let msg6 = Message(content: "Tool Result", role: .tool, toolCallId: toolCall.id.uuidString)
        messages.append(msg6)

        // 7-16: Filler to push 5/6 out of recent buffer (10 messages)
        // Messages 7 to 16 are 10 messages.
        // So 0..6 are "older".
        for i in 7...16 {
            messages.append(Message(content: "Recent \(i)", role: .user))
        }

        let collapsed = await compressor.summarizeToolInteractions(in: messages)

        // Expected:
        // Msg 0-4 (5 messages)
        // Msg 5 and 6 should be collapsed into 1 summary message
        // Msg 7-16 (10 messages) preserved
        // Total = 5 + 1 + 10 = 16 messages. Original was 17.

        XCTAssertEqual(collapsed.count, 16)

        // Verify the summary
        let summaryMsg = collapsed[5]
        XCTAssertEqual(summaryMsg.role, .summary)
        XCTAssertTrue(summaryMsg.content.contains("Tool Interaction"))

        // Verify continuity
        XCTAssertEqual(collapsed[0].content, "Msg 0")
        XCTAssertEqual(collapsed[6].content, "Recent 7")
    }

    func testRecursiveSummarize() async {
        // Create enough messages to trigger summarization
        // Recursive summarization tries to fit targetTokens.

        // Create 20 "older" messages (outside buffer of 10)
        // Total 30 messages.
        var messages: [Message] = []
        for i in 0..<30 {
             messages.append(Message(content: "Message content \(i)", role: .user))
        }

        // Assume each message is ~3-4 tokens. 30 messages ~ 100 tokens.
        // Let's set target very low to force compression.
        // Recent buffer (10 messages) will take ~30 tokens.
        // We set target to 40 tokens. So older 20 messages must compress to ~10 tokens.

        let compressed = await compressor.recursiveSummarize(
            messages: messages,
            targetTokens: 40, // Very tight constraint
            llmService: mockLLM
        )

        // We expect older messages to be summarized.
        // Recent 10 messages should be preserved.
        // Older messages should be replaced by summaries.

        let recentStart = compressed.count - 10
        XCTAssertTrue(recentStart > 0)

        // Check recent preserved
        XCTAssertEqual(compressed.last?.content, "Message content 29")

        // Check older became summary
        let first = compressed[0]
        // Either it's a summary or a leaf if it couldn't compress enough (mock returns "Summary content" which is 2 tokens)
        XCTAssertEqual(first.role, .summary)
        XCTAssertEqual(first.content, "Summary content")
    }
}

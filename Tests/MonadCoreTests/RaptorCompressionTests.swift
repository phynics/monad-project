import Testing
import Foundation
@testable import MonadCore
import MonadShared
import OpenAI
import MonadPrompt

// Mock for LLMServiceProtocol
actor RaptorMockLLMService: LLMServiceProtocol {
    var isConfigured: Bool { get async { true } }
    var configuration: LLMConfiguration { 
        get async { 
            .init(activeProvider: .openAI, providers: [:], memoryContextLimit: 0, documentContextLimit: 0, version: 1) 
        } 
    }

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

    func chatStreamWithContext(userQuery: String, contextNotes: [ContextFile], memories: [Memory], chatHistory: [Message], tools: [AnyTool], systemInstructions: String?, responseFormat: ChatQuery.ResponseFormat?, useFastModel: Bool) async -> (stream: AsyncThrowingStream<ChatStreamResult, Error>, rawPrompt: String, structuredContext: [String: String]) {
        return (AsyncThrowingStream { _ in }, "", [:])
    }

    func chatStream(messages: [ChatQuery.ChatCompletionMessageParam], tools: [ChatQuery.ChatCompletionToolParam]?, responseFormat: ChatQuery.ResponseFormat?) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        return AsyncThrowingStream { _ in }
    }

    func buildPrompt(userQuery: String, contextNotes: [ContextFile], memories: [Memory], chatHistory: [Message], tools: [AnyTool], systemInstructions: String?) async -> (messages: [ChatQuery.ChatCompletionMessageParam], rawPrompt: String, structuredContext: [String: String]) {
        return ([], "", [:])
    }

    func buildContext(userQuery: String, contextNotes: [ContextFile], memories: [Memory], chatHistory: [Message], tools: [AnyTool], systemInstructions: String?) async -> Prompt {
        return Prompt(sections: [])
    }

    func generateTags(for text: String) async throws -> [String] { return [] }
    func generateTitle(for messages: [Message]) async throws -> String { return "Title" }
    func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws -> [String: Double] { return [:] }
    func fetchAvailableModels() async throws -> [String]? { return [] }

    func getHealthStatus() async -> MonadCore.HealthStatus { .ok }
    func getHealthDetails() async -> [String: String]? { [:] }
    func checkHealth() async -> MonadCore.HealthStatus { .ok }
}

@Suite("Raptor Compression Tests")
@MainActor
struct RaptorCompressionTests {

    @Test("Summarize Tool Interactions")
    func testSummarizeToolInteractions() async {
        let compressor = ContextCompressor()
        var messages: [Message] = []

        for i in 0..<5 {
            messages.append(Message.fixture(content: "Msg \(i)"))
        }

        let toolCall = ToolCall(name: "test_tool", arguments: [:])
        var msg5 = Message.fixture(role: .assistant, content: "Calling tool")
        msg5.toolCalls = [toolCall]
        messages.append(msg5)

        let msg6 = Message.fixture(role: .tool, content: "Tool Result")
        var tcMsg6 = msg6
        tcMsg6.toolCallId = toolCall.id.uuidString
        messages.append(tcMsg6)

        for i in 7...16 {
            messages.append(Message.fixture(content: "Recent \(i)"))
        }

        let collapsed = await compressor.summarizeToolInteractions(in: messages)

        #expect(collapsed.count == 16)

        let summaryMsg = collapsed[5]
        #expect(summaryMsg.role == .summary)
        #expect(summaryMsg.content.contains("Tool Interaction"))

        #expect(collapsed[0].content == "Msg 0")
        #expect(collapsed[6].content == "Recent 7")
    }

    @Test("Recursive Summarize")
    func testRecursiveSummarize() async {
        let compressor = ContextCompressor()
        let mockLLM = RaptorMockLLMService()
        
        var messages: [Message] = []
        for i in 0..<30 {
             messages.append(Message.fixture(content: "Message content \(i)"))
        }

        let compressed = await compressor.recursiveSummarize(
            messages: messages,
            targetTokens: 40,
            llmService: mockLLM
        )

        let recentStart = compressed.count - 10
        #expect(recentStart > 0)

        #expect(compressed.last?.content == "Message content 29")

        let first = compressed[0]
        #expect(first.role == .summary)
        #expect(first.content == "Summary content")
    }
}

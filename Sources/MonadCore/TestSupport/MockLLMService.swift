import MonadShared
import Foundation
import OpenAI
import MonadPrompt

public final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    public var nextResponse: String = ""
    public var nextResponses: [String] = []
    public var lastMessages: [ChatQuery.ChatCompletionMessageParam] = []
    public var shouldThrowError: Bool = false

    // Support for tool calls in stream - use dictionaries to avoid type issues
    public var nextToolCalls: [[[String: Any]]] = []
    
    /// Support for multi-chunk streaming. If not empty, this takes precedence over nextResponse.
    public var nextChunks: [[String]] = []

    /// Optional delay between chunks for testing cancellation
    public var nextStreamWait: TimeInterval? = nil

    public init() {}

    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        lastMessages = messages

        if shouldThrowError {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NSError(domain: "MockError", code: 1, userInfo: nil))
            }
        }

        let responses = nextChunks.isEmpty ? [nextResponses.isEmpty ? nextResponse : nextResponses.removeFirst()] : nextChunks.removeFirst()
        let toolCalls = nextToolCalls.isEmpty ? nil : nextToolCalls.removeFirst()
        let wait = nextStreamWait

        struct StreamContext: @unchecked Sendable {
            let responses: [String]
            let toolCalls: [[String: Any]]?
            let wait: TimeInterval?
        }
        let ctx = StreamContext(responses: responses, toolCalls: toolCalls, wait: wait)

        return AsyncThrowingStream { continuation in
            let task = Task {
                for (index, chunk) in ctx.responses.enumerated() {
                    if Task.isCancelled { 
                        continuation.finish(throwing: CancellationError())
                        return 
                    }
                    
                    if let wait = ctx.wait {
                        do {
                            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    
                    if Task.isCancelled { 
                        continuation.finish(throwing: CancellationError())
                        return 
                    }

                    var delta: [String: Any] = [
                        "role": "assistant",
                        "content": chunk
                    ]

                    if let tc = ctx.toolCalls, index == ctx.responses.count - 1 {
                        let indexedTC = tc.enumerated().map { (idx, dict) in
                            var newDict = dict
                            newDict["index"] = idx
                            return newDict
                        }
                        delta["tool_calls"] = indexedTC
                    }

                    let jsonDict: [String: Any] = [
                        "id": "mock",
                        "object": "chat.completion.chunk",
                        "created": Date().timeIntervalSince1970,
                        "model": "mock-model",
                        "choices": [
                            [
                                "index": 0,
                                "delta": delta,
                                "finish_reason": (index == ctx.responses.count - 1 && ctx.toolCalls != nil) ? "tool_calls" : (index == ctx.responses.count - 1 ? "stop" : nil)
                            ]
                        ]
                    ]

                    do {
                        let data = try JSONSerialization.data(withJSONObject: jsonDict)
                        let result = try JSONDecoder().decode(ChatStreamResult.self, from: data)
                        continuation.yield(result)
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }
                continuation.finish()
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?) async throws
        -> String {
        if shouldThrowError {
            throw NSError(
                domain: "MockError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated failure"])
        }
        lastMessages = [.user(.init(content: .string(content)))]
        return nextResponse
    }
}

public final class MockLLMService: LLMServiceProtocol, @unchecked Sendable, HealthCheckable {
    public var mockHealthStatus: MonadCore.HealthStatus = .ok
    public var mockHealthDetails: [String: String]? = ["mock": "true"]

    public func getHealthStatus() async -> MonadCore.HealthStatus { mockHealthStatus }
    public func getHealthDetails() async -> [String: String]? { mockHealthDetails }

    public func checkHealth() async -> MonadCore.HealthStatus {
        return mockHealthStatus
    }

    public var isConfigured: Bool = true
    public var configuration: LLMConfiguration = .openAI
    public var nextResponse: String = ""
    public var nextTags: [String] = []
    public var mockClient = MockLLMClient()

    public init() {}

    public func loadConfiguration() async {}
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        self.configuration = config
    }
    public func clearConfiguration() async {
        isConfigured = false
    }
    public func restoreFromBackup() async throws {}
    public func exportConfiguration() async throws -> Data { return Data() }
    public func importConfiguration(from data: Data) async throws {}

    public func sendMessage(_ content: String) async throws -> String {
        return nextResponse
    }

    public func sendMessage(
        _ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool
    ) async throws -> String {
        return nextResponse
    }

    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        systemInstructions: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let stream = await mockClient.chatStream(
            messages: [], tools: nil, responseFormat: responseFormat)
        return (stream, "mock prompt", [:])
    }

    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        let stream = await mockClient.chatStream(
            messages: messages, tools: tools, responseFormat: responseFormat)
        return stream
    }

    public func buildPrompt(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return ([], "mock prompt", [:])
    }
    
    public func buildContext(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        systemInstructions: String?
    ) async -> Prompt {
        return Prompt(sections: [])
    }

    public func generateTags(for text: String) async throws -> [String] {
        return nextTags
    }

    public func generateTitle(for messages: [Message]) async throws -> String {
        return "Mock Title"
    }

    public func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws
        -> [String: Double] {
        return [:]
    }

    public func fetchAvailableModels() async throws -> [String]? {
        return ["mock-model"]
    }
}

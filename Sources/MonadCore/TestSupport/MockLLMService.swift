import Foundation

import OpenAI

public final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    public var nextResponse: String = ""
    public var nextResponses: [String] = []
    public var lastMessages: [ChatQuery.ChatCompletionMessageParam] = []
    public var shouldThrowError: Bool = false

    // Support for tool calls in stream - use dictionaries to avoid type issues
    public var nextToolCalls: [[[String: Any]]] = []

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

        let response = nextResponses.isEmpty ? nextResponse : nextResponses.removeFirst()
        let toolCalls = nextToolCalls.isEmpty ? nil : nextToolCalls.removeFirst()

        return AsyncThrowingStream { continuation in
            var delta: [String: Any] = [
                "role": "assistant",
                "content": response
            ]

            if let tc = toolCalls {
                delta["tool_calls"] = tc
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
                        "finish_reason": toolCalls != nil ? "tool_calls" : "stop"
                    ]
                ]
            ]

            do {
                let data = try JSONSerialization.data(withJSONObject: jsonDict)
                let result = try JSONDecoder().decode(ChatStreamResult.self, from: data)
                continuation.yield(result)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
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
    public var mockHealthStatus: HealthStatus = .ok
    public var mockHealthDetails: [String: String]? = ["mock": "true"]

    public var healthStatus: HealthStatus { get async { mockHealthStatus } }
    public var healthDetails: [String: String]? { get async { mockHealthDetails } }

    public func checkHealth() async -> HealthStatus {
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
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [any MonadCore.Tool],
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
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [any MonadCore.Tool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return ([], "mock prompt", [:])
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

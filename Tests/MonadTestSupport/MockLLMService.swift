import Foundation
import MonadCore
@testable import MonadPrompt
import MonadShared
import OpenAI

public final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    public var nextResponse: String = ""
    public var nextResponses: [String] = []
    public var lastMessages: [ChatQuery.ChatCompletionMessageParam] = []
    public var shouldThrowError: Bool = false

    /// Support for tool calls in stream - use dictionaries to avoid type issues
    public var nextToolCalls: [[[String: Any]]] = []

    /// Support for multi-chunk streaming. If not empty, this takes precedence over nextResponse.
    public var nextChunks: [[String]] = []

    /// Optional delay between chunks for testing cancellation
    public var nextStreamWait: TimeInterval?

    public init() {}

    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools _: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat _: ChatQuery.ResponseFormat?
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
                        "content": chunk,
                    ]

                    if let tc = ctx.toolCalls, index == ctx.responses.count - 1 {
                        let indexedTC = tc.enumerated().map { idx, dict in
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
                                "finish_reason": (index == ctx.responses.count - 1 && ctx.toolCalls != nil) ? "tool_calls" : (index == ctx.responses.count - 1 ? "stop" : nil),
                            ],
                        ],
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

    public func sendMessage(_ content: String, responseFormat _: ChatQuery.ResponseFormat?) async throws
        -> String
    {
        if shouldThrowError {
            throw NSError(
                domain: "MockError", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Simulated failure"]
            )
        }
        lastMessages = [.user(.init(content: .string(content)))]
        return nextResponse
    }
}

public final class MockLLMService: LLMServiceProtocol, @unchecked Sendable, HealthCheckable {
    public var mockHealthStatus: HealthStatus = .ok
    public var mockHealthDetails: [String: String]? = ["mock": "true"]

    public func getHealthStatus() async -> HealthStatus {
        mockHealthStatus
    }

    public func getHealthDetails() async -> [String: String]? {
        mockHealthDetails
    }

    public func checkHealth() async -> HealthStatus {
        return mockHealthStatus
    }

    public var mockIsConfigured: Bool = true
    public var isConfigured: Bool {
        get async { mockIsConfigured }
    }

    public var configuration: LLMConfiguration {
        get async { mockConfig }
    }

    public var mockConfig: LLMConfiguration = .openAI
    public var nextResponse: String = ""
    public var nextTags: [String] = []
    public var mockClient = MockLLMClient()

    /// Allows tests to provide a custom stream for chatStream calls.
    public var stubbedStream: AsyncThrowingStream<ChatStreamResult, Error>?

    public init() {}

    public func loadConfiguration() async {}
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        mockConfig = config
    }

    public func clearConfiguration() async {
        // can't easily change isConfigured if it's computed, but we can change mock state
    }

    public func restoreFromBackup() async throws {}
    public func exportConfiguration() async throws -> Data {
        return Data()
    }

    public func importConfiguration(from _: Data) async throws {}

    public func sendMessage(_: String) async throws -> String {
        return nextResponse
    }

    public func sendMessage(
        _: String, responseFormat _: ChatQuery.ResponseFormat?, useUtilityModel _: Bool
    ) async throws -> String {
        return nextResponse
    }

    public func chatStreamWithContext(
        userQuery _: String,
        contextNotes _: [ContextFile],
        memories _: [Memory],
        chatHistory _: [Message],
        tools _: [AnyTool],
        workspaces _: [WorkspaceReference],
        primaryWorkspace _: WorkspaceReference?,
        clientName _: String?,
        systemInstructions _: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel _: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let stream = await chatStream(messages: [], tools: nil, responseFormat: responseFormat)
        return (stream, "mock prompt", [:])
    }

    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        if let stubbed = stubbedStream {
            return stubbed
        }
        return await mockClient.chatStream(
            messages: messages, tools: tools, responseFormat: responseFormat
        )
    }

    public func buildPrompt(
        userQuery _: String,
        contextNotes _: [ContextFile],
        memories _: [Memory],
        chatHistory _: [Message],
        tools _: [AnyTool],
        workspaces _: [WorkspaceReference],
        primaryWorkspace _: WorkspaceReference?,
        clientName _: String?,
        systemInstructions _: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return ([], "mock prompt", [:])
    }

    public func buildContext(
        userQuery _: String,
        contextNotes _: [ContextFile],
        memories _: [Memory],
        chatHistory _: [Message],
        tools _: [AnyTool],
        workspaces _: [WorkspaceReference],
        primaryWorkspace _: WorkspaceReference?,
        clientName _: String?,
        systemInstructions _: String?,
        agentInstance _: AgentInstance?,
        timeline _: Timeline?,
        extensionSections _: [any ContextSection]
    ) async -> Prompt {
        return Prompt(sections: [])
    }

    public func generateTags(for _: String) async throws -> [String] {
        return nextTags
    }

    public func generateTitle(for _: [Message]) async throws -> String {
        return "Mock Title"
    }

    public func evaluateRecallPerformance(transcript _: String, recalledMemories _: [Memory]) async throws
        -> [String: Double]
    {
        return [:]
    }

    public func fetchAvailableModels() async throws -> [String]? {
        return ["mock-model"]
    }
}

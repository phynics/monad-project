import Foundation
import Logging
@testable import MonadCore
import MonadShared
import MonadTestSupport
import OpenAI
import Testing

// MARK: - Helpers

private let testLogger = Logger(label: "test.pipeline")

private func makeContext(
    fullResponse: String = "",
    accumulatedRawOutput: String = "",
    toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:],
    currentMessages: [ChatQuery.ChatCompletionMessageParam] = []
) -> ChatTurnContext {
    let outputs = TurnOutputs(priorAccumulatedOutput: accumulatedRawOutput)
    outputs.fullResponse = fullResponse
    outputs.toolCallAccumulators = toolCallAccumulators
    return ChatTurnContext(
        timelineId: UUID(),
        agentInstanceId: nil,
        modelName: "test-model",
        maxTurns: 5,
        systemInstructions: nil,
        availableTools: [],
        contextData: ContextData(),
        structuredContext: [:],
        currentMessages: currentMessages,
        turnCount: 1,
        outputs: outputs
    )
}

private func drain(_ stream: AsyncThrowingStream<ChatEvent, Error>) async throws -> [ChatEvent] {
    var events: [ChatEvent] = []
    for try await event in stream {
        events.append(event)
    }
    return events
}

// MARK: - MessagePersistenceStage Tests

@Suite final class MessagePersistenceStageBehavior {
    @Test
    func completedEventEmittedOnFinalTurn() async throws {
        let store = MockPersistenceService()
        let stage = MessagePersistenceStage(messageStore: store, logger: testLogger)
        let context = makeContext(fullResponse: "Hello!")

        let events = try await drain(await stage.process(context))

        let completions = events.compactMap { $0.completedMessage }
        #expect(completions.count == 1)
        #expect(completions[0].message.content == "Hello!")
    }

    @Test
    func noCompletedEventOnToolCallTurn() async throws {
        let store = MockPersistenceService()
        let stage = MessagePersistenceStage(messageStore: store, logger: testLogger)
        let context = makeContext(
            toolCallAccumulators: [0: (id: "call-1", name: "my_tool", args: "{}")]
        )

        let events = try await drain(await stage.process(context))

        let completions = events.compactMap { $0.completedMessage }
        #expect(completions.isEmpty)
    }

    @Test
    func debugSnapshotCapturesRenderedPromptOnFinalTurn() async throws {
        let store = MockPersistenceService()
        let stage = MessagePersistenceStage(messageStore: store, logger: testLogger)
        let context = makeContext(
            fullResponse: "done",
            accumulatedRawOutput: "done",
            currentMessages: [.user(.init(content: .string("query")))]
        )

        let events = try await drain(await stage.process(context))

        let completed = events.compactMap { $0.completedMessage }.first
        let data = try #require(completed?.metadata.debugSnapshotData)
        let snapshot = try SerializationUtils.jsonDecoder.decode(DebugSnapshot.self, from: data)
        #expect(snapshot.renderedPrompt != nil)
        #expect(snapshot.renderedPrompt?.isEmpty == false)
        #expect(snapshot.rawOutput == "done")
    }
}

// MARK: - ToolCallExtractionStage Tests

@Suite final class ToolCallExtractionStageBehavior {
    @Test
    func sentinelCallsFiltered() async throws {
        let stage = ToolCallExtractionStage(logger: testLogger)
        let context = makeContext()
        context.outputs.toolCallAccumulators[0] = (id: "s1", name: ChatEngine.Constants.sentinelToolName, args: "{}")
        context.outputs.toolCallAccumulators[1] = (id: "r1", name: "real_tool", args: "{}")

        _ = try await drain(await stage.process(context))

        #expect(context.outputs.toolCallAccumulators.count == 1)
        #expect(context.outputs.toolCallAccumulators.values.first?.name == "real_tool")
    }

    @Test
    func emptyNameCallsFiltered() async throws {
        let stage = ToolCallExtractionStage(logger: testLogger)
        let context = makeContext()
        context.outputs.toolCallAccumulators[0] = (id: "e1", name: "", args: "{}")
        context.outputs.toolCallAccumulators[1] = (id: "k1", name: "valid_tool", args: "{}")

        _ = try await drain(await stage.process(context))

        #expect(context.outputs.toolCallAccumulators.count == 1)
        #expect(context.outputs.toolCallAccumulators.values.first?.name == "valid_tool")
    }

    @Test
    func fallbackTextParsingTriggered() async throws {
        let stage = ToolCallExtractionStage(logger: testLogger)
        let context = makeContext(
            fullResponse: #"<tool_call>{"name": "test_tool", "arguments": {"key": "val"}}</tool_call>"#
        )

        _ = try await drain(await stage.process(context))

        #expect(!context.outputs.toolCallAccumulators.isEmpty)
        #expect(context.outputs.toolCallAccumulators.values.contains { $0.name == "test_tool" })
    }
}

// MARK: - LLMStreamingStage Tests

@Suite final class LLMStreamingStageBehavior {
    @Test
    func thinkingAndContentSeparated() async throws {
        let mockService = MockLLMService()
        mockService.mockClient.nextResponse = "<think>reasoning here</think>content here"
        let stage = LLMStreamingStage(llmService: mockService, logger: testLogger)
        let context = makeContext()

        let events = try await drain(await stage.process(context))

        let thinking = events.compactMap { $0.thinkingContent }.joined()
        let content = events.compactMap { $0.textContent }.joined()
        #expect(thinking.contains("reasoning here"))
        #expect(content.contains("content here"))
        #expect(context.outputs.fullThinking.contains("reasoning here"))
        #expect(context.outputs.fullResponse.contains("content here"))
    }

    @Test
    func toolCallDeltasEmitted() async throws {
        let mockService = MockLLMService()
        mockService.mockClient.nextResponse = ""
        mockService.mockClient.nextToolCalls = [[
            [
                "id": "tc-1",
                "type": "function",
                "function": ["name": "my_tool", "arguments": "{\"x\": 1}"],
            ],
        ]]
        let stage = LLMStreamingStage(llmService: mockService, logger: testLogger)
        let context = makeContext()

        let events = try await drain(await stage.process(context))

        let toolCallDeltas = events.filter {
            if case .delta(.toolCall) = $0 { return true }
            return false
        }
        #expect(!toolCallDeltas.isEmpty)
        #expect(!context.outputs.toolCallAccumulators.isEmpty)
    }
}

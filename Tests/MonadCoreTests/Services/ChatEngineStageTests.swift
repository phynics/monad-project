import Foundation
import Logging
@testable import MonadCore
import MonadShared
import MonadTestSupport
import OpenAI
import Testing

@Suite final class ChatEngineStageTests {
    private let logger = Logger(label: "test")

    @Test
    func toolExecutionStage_TextFallback() async throws {
        // Given
        let context = createTestContext()
        context.outputs.fullResponse = #"<tool_call>{"name": "test_tool", "arguments": {"foo": "bar"}}</tool_call>"#

        let stage = ToolCallExtractionStage(logger: logger)

        // When
        let stream = try await stage.process(context)
        for try await _ in stream {}

        // Then
        #expect(context.outputs.toolCallAccumulators.count == 1)
        #expect(context.outputs.toolCallAccumulators[0]?.name == "test_tool")
        #expect(context.outputs.debugToolCalls.count == 1)
        #expect(context.outputs.debugToolCalls[0].name == "test_tool")
    }

    @Test
    func persistenceStage_SavesMessage() async throws {
        // Given
        let persistence = MockPersistenceService()
        _ = TimelineManager(workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let stage = MessagePersistenceStage(messageStore: persistence, logger: logger)

        let context = createTestContext()
        context.outputs.fullResponse = "Hello world"

        // When
        let stream = try await stage.process(context)
        for try await _ in stream {}

        // Then
        #expect(persistence.messages.count == 1)
        #expect(persistence.messages[0].content == "Hello world")
    }

    // MARK: - Helpers

    private func createTestContext() -> ChatTurnContext {
        let outputs = TurnOutputs()
        return ChatTurnContext(
            timelineId: UUID(),
            agentInstanceId: nil,
            modelName: "test-model",
            maxTurns: 5,
            systemInstructions: nil,
            availableTools: [],
            contextData: ContextData(),
            structuredContext: [:],
            currentMessages: [],
            turnCount: 1,
            outputs: outputs
        )
    }
}

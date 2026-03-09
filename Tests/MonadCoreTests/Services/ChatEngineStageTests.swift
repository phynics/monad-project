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
        var context = createTestContext()
        context.fullResponse = #"<tool_call>{"name": "test_tool", "arguments": {"foo": "bar"}}</tool_call>"#

        let stage = ToolExecutionStage(logger: logger)

        // When
        try await stage.process(&context)

        // Then
        #expect(context.toolCallAccumulators.count == 1)
        #expect(context.toolCallAccumulators[0]?.name == "test_tool")
        #expect(context.debugToolCalls.count == 1)
        #expect(context.debugToolCalls[0].name == "test_tool")
    }

    @Test

    func persistenceStage_SavesMessage() async throws {
        // Given
        let persistence = MockPersistenceService()
        let timelineManager = TimelineManager(workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let stage = PersistenceStage(messageStore: persistence, logger: logger)

        var context = createTestContext()
        context.fullResponse = "Hello world"
        context.turnResult = .finish

        // When
        try await stage.process(&context)

        // Then
        #expect(persistence.messages.count == 1)
        #expect(persistence.messages[0].content == "Hello world")
    }

    // MARK: - Helpers

    private func createTestContext() -> ChatTurnContext {
        let (_, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        return ChatTurnContext(
            timelineId: UUID(),
            agentInstanceId: nil,
            modelName: "test-model",
            turnCount: 1,
            currentMessages: [],
            toolParams: [],
            availableTools: [],
            contextData: ContextData(notes: [], memories: [], generatedTags: [], queryVector: [], augmentedQuery: "", semanticResults: [], tagResults: [], executionTime: 0),
            structuredContext: [:],
            continuation: continuation
        )
    }
}

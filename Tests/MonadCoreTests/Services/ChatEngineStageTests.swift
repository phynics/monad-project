import XCTest
import Logging
import MonadShared
import MonadTestSupport
import OpenAI
@testable import MonadCore

final class ChatEngineStageTests: XCTestCase {
    
    private let logger = Logger(label: "test")
    
    func testToolExecutionStage_TextFallback() async throws {
        // Given
        var context = createTestContext()
        context.fullResponse = #"<tool_call>{"name": "test_tool", "arguments": {"foo": "bar"}}</tool_call>"#
        
        let expectation = XCTestExpectation(description: "Tool execution closure called")
        
        let stage = ChatEngine.ToolExecutionStage(executeTools: { calls, tools, turn, cont in
            XCTAssertEqual(calls.count, 1)
            XCTAssertEqual(calls[0].function.name, "test_tool")
            expectation.fulfill()
            return ([], false, [])
        }, logger: logger)
        
        // When
        try await stage.process(&context)
        
        // Then
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(context.debugToolCalls.count, 1)
        XCTAssertEqual(context.debugToolCalls[0].name, "test_tool")
    }
    
    func testPersistenceStage_SavesMessage() async throws {
        // Given
        let persistence = MockPersistenceService()
        let timelineManager = TimelineManager(workspaceRoot: URL(fileURLWithPath: "/tmp"))
        let stage = ChatEngine.PersistenceStage(persistenceService: persistence, timelineManager: timelineManager, logger: logger)
        
        var context = createTestContext()
        context.fullResponse = "Hello world"
        context.turnResult = .finish
        
        // When
        try await stage.process(&context)
        
        // Then
        XCTAssertEqual(persistence.messages.count, 1)
        XCTAssertEqual(persistence.messages[0].content, "Hello world")
    }
    
    // MARK: - Helpers
    
    private func createTestContext() -> ChatEngine.ChatTurnContext {
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        return ChatEngine.ChatTurnContext(
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

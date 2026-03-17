import Foundation
import XCTest
import Dependencies
@testable import MonadCore
@testable import MonadShared
import MonadTestSupport

final class MonadChatTests: XCTestCase {
    func testBasicExecution() async throws {
        let mockLLM = MockLLMService()
        let mockStore = MockMessageStore()
        let mockPersistence = MockPersistenceService()
        
        let timelineId = UUID()
        let message = "Hello, Morty!"
        
        try await mockPersistence.saveTimeline(Timeline(id: timelineId, title: "Test"))
        
        let chat = MonadChat(llmService: mockLLM, messageStore: mockStore)
        
        // Use the new fluent execute method, providing required test dependencies
        let stream = try await withDependencies {
            $0.timelinePersistence = mockPersistence
            $0.workspacePersistence = mockPersistence
            $0.memoryStore = mockPersistence
            $0.agentTemplateStore = mockPersistence
            $0.clientStore = mockPersistence
            $0.toolPersistence = mockPersistence
            $0.agentInstanceStore = mockPersistence
            $0.timelineManager = TimelineManager(workspaceRoot: URL(fileURLWithPath: "/tmp/monad-test"), workspaceCreator: MockWorkspaceCreator())
            $0.toolRouter = ToolRouter()
        } operation: {
            try await chat.execute(
                timelineId: timelineId,
                message: message
            )
        }
        
        XCTAssertNotNil(stream)
    }

    actor MockStageRunTracker {
        var didRun = false
        func setRun() { didRun = true }
    }

    struct MockCustomStage: PipelineStage {
        let tracker: MockStageRunTracker
        var id: String { "MockCustomStage" }
        
        func process(_ context: ChatTurnContext) async throws -> AsyncThrowingStream<ChatEvent, Error> {
            await tracker.setRun()
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    }

    func testCustomPipelineStage() async throws {
        let mockLLM = MockLLMService()
        let mockStore = MockMessageStore()
        let mockPersistence = MockPersistenceService()
        
        let timelineId = UUID()
        let message = "Hello, custom stage!"
        
        try await mockPersistence.saveTimeline(Timeline(id: timelineId, title: "Test"))
        
        let tracker = MockStageRunTracker()
        let customStage = MockCustomStage(tracker: tracker)
        
        let chat = MonadChat(llmService: mockLLM, messageStore: mockStore)
            .addStage(customStage)
        
        let stream = try await withDependencies {
            $0.timelinePersistence = mockPersistence
            $0.workspacePersistence = mockPersistence
            $0.memoryStore = mockPersistence
            $0.agentTemplateStore = mockPersistence
            $0.clientStore = mockPersistence
            $0.toolPersistence = mockPersistence
            $0.agentInstanceStore = mockPersistence
            $0.timelineManager = TimelineManager(workspaceRoot: URL(fileURLWithPath: "/tmp/monad-test"), workspaceCreator: MockWorkspaceCreator())
            $0.toolRouter = ToolRouter()
        } operation: {
            try await chat.execute(
                timelineId: timelineId,
                message: message
            )
        }
        
        for try await _ in stream {}
        
        let didRun = await tracker.didRun
        XCTAssertTrue(didRun, "Custom stage should have been executed")
    }
}

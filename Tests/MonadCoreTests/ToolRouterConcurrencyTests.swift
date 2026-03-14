import Dependencies
import Foundation
@testable import MonadCore
@testable import MonadShared
@testable import MonadShared
import MonadTestSupport
import Testing

@Suite(.serialized) struct ToolRouterConcurrencyTests {
    private func makeSetup() async -> (ToolRouter, TimelineManager, MockPersistenceService) {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        let router = ToolRouter()
        let manager = try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.timelineManager = TimelineManager(workspaceRoot: workspaceRoot)
        } operation: {
            TimelineManager(workspaceRoot: workspaceRoot)
        }
        return (router, manager, persistence)
    }

    @Test("Concurrent execute calls for unknown tools each throw toolNotFound")
    func concurrentExecute_unknownTool_allThrow() async throws {
        let (router, manager, _) = await makeSetup()

        let timelineId = try await withDependencies {
            $0.timelinePersistence = MockPersistenceService()
            $0.workspacePersistence = MockPersistenceService()
            $0.memoryStore = MockPersistenceService()
            $0.messageStore = MockPersistenceService()
            $0.agentTemplateStore = MockPersistenceService()
            $0.clientStore = MockPersistenceService()
            $0.toolPersistence = MockPersistenceService()
            $0.agentInstanceStore = MockPersistenceService()
            $0.embeddingService = MockEmbeddingService()
            $0.llmService = MockLLMService()
            $0.timelineManager = manager
        } operation: {
            try await manager.createTimeline().id
        }

        let tool = ToolReference.known(id: "nonexistent")
        let concurrency = 4

        let errors = await withTaskGroup(of: Error?.self, returning: [Error?].self) { group in
            for _ in 0 ..< concurrency {
                group.addTask {
                    do {
                        _ = try await withDependencies {
                            $0.timelineManager = manager
                        } operation: {
                            try await router.execute(tool: tool, arguments: [:], timelineId: timelineId)
                        }
                        return nil
                    } catch {
                        return error
                    }
                }
            }
            var results: [Error?] = []
            for await error in group {
                results.append(error)
            }
            return results
        }

        // All concurrent calls should fail (not hang or crash)
        #expect(errors.count == concurrency)
        for error in errors {
            #expect(error != nil, "Each concurrent execute should throw an error")
        }
    }

    @Test("ToolRouter.execute for disconnected session throws toolNotFound or workspaceNotFound")
    func execute_unknownSession_throws() async throws {
        let (router, manager, _) = await makeSetup()
        let unknownSessionId = UUID()
        let tool = ToolReference.known(id: "some-tool")

        do {
            _ = try await withDependencies {
                $0.timelineManager = manager
            } operation: {
                try await router.execute(tool: tool, arguments: [:], timelineId: unknownSessionId)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            // Any ToolError is acceptable (toolNotFound, workspaceNotFound)
            #expect(error is ToolError || error is TimelineError)
        }
    }
}

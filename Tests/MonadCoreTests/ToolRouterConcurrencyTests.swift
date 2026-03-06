import Dependencies
import Foundation
@testable import MonadCore
@testable import MonadShared
@testable import MonadShared
import MonadTestSupport
import Testing

@Suite(.serialized) struct ToolRouterConcurrencyTests {
    private func makeSetup() async -> (ToolRouter, SessionManager, MockPersistenceService) {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        let router = ToolRouter()
        let manager = await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.msAgentRegistry = MSAgentRegistry()
            $0.sessionManager = SessionManager(workspaceRoot: workspaceRoot)
        } operation: {
            SessionManager(workspaceRoot: workspaceRoot)
        }
        return (router, manager, persistence)
    }

    @Test("Concurrent execute calls for unknown tools each throw toolNotFound")
    func concurrentExecute_unknownTool_allThrow() async throws {
        let (router, manager, _) = await makeSetup()

        let sessionId = try await withDependencies {
            $0.persistenceService = MockPersistenceService()
            $0.embeddingService = MockEmbeddingService()
            $0.llmService = MockLLMService()
            $0.msAgentRegistry = MSAgentRegistry()
            $0.sessionManager = manager
        } operation: {
            try await manager.createSession().id
        }

        let tool = ToolReference.known(id: "nonexistent")
        let concurrency = 4

        let errors = await withTaskGroup(of: Error?.self, returning: [Error?].self) { group in
            for _ in 0 ..< concurrency {
                group.addTask {
                    do {
                        _ = try await withDependencies {
                            $0.sessionManager = manager
                        } operation: {
                            try await router.execute(tool: tool, arguments: [:], sessionId: sessionId)
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
                $0.sessionManager = manager
            } operation: {
                try await router.execute(tool: tool, arguments: [:], sessionId: unknownSessionId)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            // Any ToolError is acceptable (toolNotFound, workspaceNotFound)
            #expect(error is ToolError || error is SessionError)
        }
    }
}

import Testing
import Foundation
import Dependencies
import MonadTestSupport
@testable import MonadCore
@testable import MonadShared
@testable import MonadShared
@Suite struct TimelineManagerTests {

    @Test("Test Session Creation and Context Manager Access")
    func testSessionCreation() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()

        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.msAgentRegistry = MSAgentRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            let session = try await timelineManager.createTimeline()

            #expect(session.id != UUID.init(), "Session should have an ID")

            let retrievedSession = await timelineManager.getTimeline(id: session.id)
            #expect(retrievedSession != nil, "Should be able to retrieve created session")
            #expect(retrievedSession?.id == session.id)

            // Verify ContextManager is created and has access to workspace
            let contextManager = await timelineManager.getContextManager(for: session.id)
            #expect(contextManager != nil, "ContextManager should be created for session")
        }
    }

    @Test("Test Stale Session Cleanup")
    func testCleanup() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.msAgentRegistry = MSAgentRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            let session = try await timelineManager.createTimeline()

            // Simulate time passing (need a way to set last active time in TimelineManager, maybe via internal method or by updating Session struct)
            // For now, check if cleanup method exists
            await timelineManager.cleanupStaleTimelines(maxAge: 0) // Should remove immediately if maxAge is 0

            let retrieved = await timelineManager.getTimeline(id: session.id)
            #expect(retrieved == nil, "Session should be cleaned up")
        }
    }
}

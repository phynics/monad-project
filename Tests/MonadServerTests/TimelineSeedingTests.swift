import MonadShared
import MonadCore
import XCTest
import Dependencies
import MonadTestSupport
@testable import MonadServer

final class SessionSeedingTests: XCTestCase {
    var persistence: MockPersistenceService!
    var workspaceRoot: URL!

    override func setUp() async throws {
        persistence = MockPersistenceService()
        workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    }

    func testSessionSeeding() async throws {
        try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.msAgentStore = persistence
            $0.backgroundJobStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = MockEmbeddingService()
            $0.llmService = MockLLMService()
            $0.msAgentRegistry = MSAgentRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            let session = try await timelineManager.createTimeline(title: "Test Session")

            let sessionDir = workspaceRoot.appendingPathComponent("timelines").appendingPathComponent(session.id.uuidString)
            let notesDir = sessionDir.appendingPathComponent("Notes")
            XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Welcome.md").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Project.md").path))
        }
    }
}

import Dependencies
import GRDB
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import XCTest

final class SessionWorkspaceTests: XCTestCase {
    var persistenceService: PersistenceService!
    var embeddingService: MockEmbeddingService!
    var llmService: MockLLMService!
    var workspaceRoot: URL!

    override func setUp() async throws {
        // Setup in-memory database with full schema for realistic integration testing
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)

        persistenceService = PersistenceService(dbQueue: dbQueue)
        embeddingService = MockEmbeddingService()
        llmService = MockLLMService()

        workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    }

    func testCreateSessionCreatesDedicatedWorkspace() async throws {
        try await withDependencies {
            $0.workspacePersistence = persistenceService.workspaceStore
            $0.timelinePersistence = persistenceService.timelineStore
            $0.toolPersistence = persistenceService.toolStore
            $0.memoryStore = persistenceService.memoryStore
            $0.messageStore = persistenceService.messageStore
            $0.agentTemplateStore = persistenceService.agentTemplateStore
            $0.backgroundJobStore = persistenceService.backgroundJobStore
            $0.clientStore = persistenceService.clientStore
            $0.agentInstanceStore = persistenceService.agentInstanceStore
            $0.embeddingService = embeddingService
            $0.llmService = llmService
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            // Act
            let session = try await timelineManager.createTimeline(title: "Workspace Test Session")

            // Assert
            XCTAssertNotNil(session.primaryWorkspaceId, "Session should have a primary workspace ID")

            // Verify workspace exists in DB
            let workspace = try await persistenceService.dbQueue.read { db in
                try WorkspaceReference.fetchOne(db, key: session.primaryWorkspaceId)
            }

            XCTAssertNotNil(workspace, "Primary workspace record should exist in database")
            XCTAssertEqual(workspace?.hostType, WorkspaceReference.WorkspaceHostType.server, "Primary workspace should be hosted on server")
            XCTAssertEqual(workspace?.uri.path, "/sessions/\(session.id.uuidString)", "Workspace URI path should match session ID convention")
        }
    }
}

import Dependencies
import Foundation
import GRDB
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import Testing

@Suite final class SessionWorkspaceTests {
    var persistenceService: PersistenceService!
    var embeddingService: MockEmbeddingService!
    var llmService: MockLLMService!
    var workspaceRoot: URL!

    init() async throws {
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

    @Test

    func createSessionCreatesDedicatedWorkspace() async throws {
        let persistenceService = try #require(persistenceService)
        let embeddingService = try #require(embeddingService)
        let llmService = try #require(llmService)
        let workspaceRoot = try #require(workspaceRoot)
        try await TestDependencies()
            .withMocks()
            .with {
                $0.workspacePersistence = persistenceService.workspaceStore
                $0.timelinePersistence = persistenceService.timelineStore
                $0.toolPersistence = persistenceService.toolStore
                $0.memoryStore = persistenceService.memoryStore
                $0.messageStore = persistenceService.messageStore
                $0.agentTemplateStore = persistenceService.agentTemplateStore
                $0.clientStore = persistenceService.clientStore
                $0.agentInstanceStore = persistenceService.agentInstanceStore
                $0.embeddingService = embeddingService
                $0.llmService = llmService
            }
            .run {
                let timelineManager = TimelineManager(
                    workspaceRoot: workspaceRoot
                )

                // Act
                let session = try await timelineManager.createTimeline(title: "Workspace Test Session")

                // Assert
                try #require(!session.attachedWorkspaceIds.isEmpty)

                // Verify workspace exists in DB
                let workspace = try await persistenceService.dbQueue.read { db in
                    try WorkspaceReference.fetchOne(db, key: session.attachedWorkspaceIds.first)
                }

                try #require(workspace != nil)
                #expect(workspace?.hostType == WorkspaceReference.WorkspaceHostType.server)
                #expect(workspace?.uri.path == "/sessions/\(session.id.uuidString)")
            }
    }
}

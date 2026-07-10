import Foundation
import GRDB
@testable import MonadServerCore
import MonadShared
import PKShared
import PKTestSupport
import PositronicKit
import Testing

final class SessionWorkspaceTests {
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
        let workspaceRoot = try #require(workspaceRoot)
        let timelineManager = TimelineManager(
            stores: .init(
                timelineStore: persistenceService.timelineStore,
                messageStore: persistenceService.messageStore,
                workspaceStore: persistenceService.workspaceStore,
                toolPersistence: persistenceService.toolStore
            ),
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
        #expect(workspace?.location == .runtime)
        #expect(workspace?.uri.path == "/timelines/\(session.id.uuidString)")
    }
}

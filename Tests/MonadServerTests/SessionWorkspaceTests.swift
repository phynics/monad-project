import XCTest
import GRDB
@testable import MonadCore
@testable import MonadServer
import Dependencies

final class SessionWorkspaceTests: XCTestCase {
    var persistenceService: MockPersistenceService!
    var embeddingService: MockEmbeddingService!
    var llmService: MockLLMService!
    var workspaceRoot: URL!

    override func setUp() async throws {
        // Setup in-memory database with full schema for realistic integration testing
        let dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)

        persistenceService = MockPersistenceService(databaseWriter: dbQueue)
        embeddingService = MockEmbeddingService()
        llmService = MockLLMService()

        workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    }

    func testCreateSessionCreatesDedicatedWorkspace() async throws {
        try await withDependencies {
            $0.persistenceService = persistenceService
            $0.embeddingService = embeddingService
            $0.llmService = llmService
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
            
            // Act
            let session = try await sessionManager.createSession(title: "Workspace Test Session")
    
            // Assert
            XCTAssertNotNil(session.primaryWorkspaceId, "Session should have a primary workspace ID")
    
            // Verify workspace exists in DB
            let workspace = try await persistenceService.databaseWriter.read { db in
                try WorkspaceReference.fetchOne(db, key: session.primaryWorkspaceId)
            }
    
            XCTAssertNotNil(workspace, "Primary workspace record should exist in database")
            XCTAssertEqual(workspace?.hostType, .server, "Primary workspace should be hosted on server")
            XCTAssertEqual(workspace?.uri.path, "/sessions/\(session.id.uuidString)", "Workspace URI path should match session ID convention")
        }
    }
}

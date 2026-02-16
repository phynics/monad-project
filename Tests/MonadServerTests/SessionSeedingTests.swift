import MonadShared
import XCTest
import MonadCore
import Dependencies
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
            $0.persistenceService = persistence
            $0.embeddingService = MockEmbeddingService()
            $0.llmService = MockLLMService()
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
            
            let session = try await sessionManager.createSession(title: "Test Session")
    
            let sessionDir = workspaceRoot.appendingPathComponent("sessions").appendingPathComponent(session.id.uuidString)
            let notesDir = sessionDir.appendingPathComponent("Notes")
            XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Welcome.md").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Project.md").path))
        }
    }
}

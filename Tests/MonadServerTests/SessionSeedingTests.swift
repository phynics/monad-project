import XCTest
import MonadCore
@testable import MonadServer

final class SessionSeedingTests: XCTestCase {
    var sessionManager: SessionManager!
    var persistence: MockPersistenceService!
    var workspaceRoot: URL!

    override func setUp() async throws {
        persistence = MockPersistenceService()
        workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

        sessionManager = SessionManager(
            persistenceService: persistence,
            embeddingService: MockEmbeddingService(),
            llmService: MockLLMService(),
            workspaceRoot: workspaceRoot
        )
    }

    func testSessionSeeding() async throws {
        let session = try await sessionManager.createSession(title: "Test Session")

        let sessionDir = workspaceRoot.appendingPathComponent("sessions").appendingPathComponent(session.id.uuidString)
        let notesDir = sessionDir.appendingPathComponent("Notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Welcome.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Project.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Persona.md").path))
    }
}

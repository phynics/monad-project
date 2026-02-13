import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer
import MonadCore
import NIOCore
import Logging

@Suite struct FilesControllerTests {

    @Test("Test Get Nested File Content (Manual Path Extraction)")
    func testGetNestedFileContent() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        
        // Create a test workspace structure
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        
        let sessionManager = SessionManager(
            persistenceService: persistence,
            embeddingService: embedding,
            llmService: llmService,
            workspaceRoot: workspaceRoot
        )

        // Create Session (which creates the workspace)
        let session = try await sessionManager.createSession(title: "Files Test Session")
        guard let workspaceId = session.primaryWorkspaceId else {
            Issue.record("Session should have a primary workspace")
            return
        }
        
        // Manually create a nested file directly in the workspace to test retrieval
        // The workspace path is .../sessions/<sessionId>
        let sessionWorkspacePath = workspaceRoot.appendingPathComponent("sessions").appendingPathComponent(session.id.uuidString)
        let noteDir = sessionWorkspacePath.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
        
        let content = "# Nested Content"
        let filePath = noteDir.appendingPathComponent("Project.md")
        try content.write(to: filePath, atomically: true, encoding: .utf8)
        
        // Setup App & Controller
        // Setup App & Controller
        let router = Router()
        let workspaceController = try await WorkspaceController(dbWriter: persistence.databaseWriter)
        let controller = FilesController<BasicRequestContext>(workspaceController: workspaceController)
        
        // Register routes similar to MonadServerApp (flattened)
        controller.addRoutes(to: router.group("/workspaces/:workspaceId/files"))

        let app = Application(router: router)

        // Test Request: GET /workspaces/:id/files/Notes/Project.md
        // This validates that the ** wildcard and manual extraction logic works
        try await app.test(.router) { client in
             try await client.execute(uri: "/workspaces/\(workspaceId)/files/Notes/Project.md", method: .get) { response in
                #expect(response.status == .ok)
                let bodyString = String(buffer: response.body)
                #expect(bodyString == content)
            }
        }
    }
    
    @Test("Test List Files")
    func testListFiles() async throws {
         // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        
        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        
        // Cleanup
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        
        let sessionManager = SessionManager(
            persistenceService: persistence,
            embeddingService: embedding,
            llmService: llmService,
            workspaceRoot: workspaceRoot
        )

        let session = try await sessionManager.createSession(title: "List Files Session")
        guard let workspaceId = session.primaryWorkspaceId else { return }
        
        // Inject fake files
        let sessionWorkspacePath = workspaceRoot.appendingPathComponent("sessions").appendingPathComponent(session.id.uuidString)
        let noteDir = sessionWorkspacePath.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
        try "Content".write(to: noteDir.appendingPathComponent("TestNote.md"), atomically: true, encoding: .utf8)
        
        
        let router = Router()
        let workspaceController = try await WorkspaceController(dbWriter: persistence.databaseWriter)
        let controller = FilesController<BasicRequestContext>(workspaceController: workspaceController)
        controller.addRoutes(to: router.group("/workspaces/:workspaceId/files"))
        let app = Application(router: router)
        
        try await app.test(.router) { client in
             try await client.execute(uri: "/workspaces/\(workspaceId)/files", method: .get) { response in
                #expect(response.status == .ok)
                // Should return JSON array
                let files = try JSONDecoder().decode([String].self, from: response.body)
                // Session creation makes Notes/Persona.md, Notes/Welcome.md, Notes/Project.md
                #expect(files.contains("Notes/Persona.md"))
            }
        }
    }
}

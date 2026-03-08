import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import NIOCore
import Testing

@Suite struct FilesControllerTests {
    @Test("Test Get Nested File Content (Manual Path Extraction)")
    func getNestedFileContent() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()

        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llmService
            $0.msAgentRegistry = MSAgentRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            // Create Timeline (which creates the workspace)
            let timeline = try await timelineManager.createTimeline(title: "Files Test Session")
            guard let workspaceId = timeline.primaryWorkspaceId,
                  let workingDirectory = timeline.workingDirectory
            else {
                Issue.record("Timeline should have a primary workspace and working directory")
                return
            }

            // Manually create a nested file directly in the workspace to test retrieval
            let timelineWorkspacePath = URL(fileURLWithPath: workingDirectory)
            let noteDir = timelineWorkspacePath.appendingPathComponent("Notes")
            try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

            let content = "# Nested Content"
            let filePath = noteDir.appendingPathComponent("TestFile.md")
            try content.write(to: filePath, atomically: true, encoding: .utf8)

            // Setup App & Controller
            let router = Router()
            let workspaceManager = WorkspaceManager(repository: WorkspaceRepository(), workspaceCreator: WorkspaceFactory())
            let controller = FilesAPIController<BasicRequestContext>(workspaceManager: workspaceManager)

            // Register routes similar to MonadServerApp (flattened)
            controller.addRoutes(to: router.group("/workspaces/:workspaceId/files"))

            let app = Application(router: router)

            // Test Request: GET /workspaces/:id/files/Notes/TestFile.md
            // This validates that the ** wildcard and manual extraction logic works
            try await app.test(.router) { client in
                try await client.execute(uri: "/workspaces/\(workspaceId)/files/Notes/TestFile.md", method: .get) { response in
                    #expect(response.status == .ok)
                    let bodyString = String(buffer: response.body)
                    #expect(bodyString == content)
                }
            }
        }
    }

    @Test("Test List Files")
    func listFiles() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()

        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

        // Cleanup
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llmService
            $0.msAgentRegistry = MSAgentRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            let timeline = try await timelineManager.createTimeline(title: "List Files Session")
            guard let workspaceId = timeline.primaryWorkspaceId,
                  let workingDirectory = timeline.workingDirectory else { return }

            // Inject fake files
            let timelineWorkspacePath = URL(fileURLWithPath: workingDirectory)
            let noteDir = timelineWorkspacePath.appendingPathComponent("Notes")
            try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
            try "Content".write(to: noteDir.appendingPathComponent("TestNote.md"), atomically: true, encoding: .utf8)

            let router = Router()
            let workspaceManager = WorkspaceManager(repository: WorkspaceRepository(), workspaceCreator: WorkspaceFactory())
            let controller = FilesAPIController<BasicRequestContext>(workspaceManager: workspaceManager)
            controller.addRoutes(to: router.group("/workspaces/:workspaceId/files"))
            let app = Application(router: router)

            try await app.test(.router) { client in
                try await client.execute(uri: "/workspaces/\(workspaceId)/files", method: .get) { response in
                    #expect(response.status == .ok)
                    // Should return JSON array
                    _ = try JSONDecoder().decode([String].self, from: response.body)
                    // Session creation makes Notes/Welcome.md, Notes/Project.md
                }
            }
        }
    }
}

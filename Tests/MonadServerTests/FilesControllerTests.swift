import Foundation
import Hummingbird
import HummingbirdTesting
import Logging
@testable import MonadServer
import MonadShared
import NIOCore
import PKShared
import PKTestSupport
import PositronicKit
import Testing

struct FilesControllerTests {
    @Test("Test Get Nested File Content (Manual Path Extraction)")
    func getNestedFileContent() async throws {
        let persistence = MockPersistenceService()

        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)

        let timelineManager = TimelineManager(
            stores: .init(
                timelineStore: persistence,
                messageStore: persistence,
                workspaceStore: persistence,
                toolPersistence: persistence
            ),
            workspaceRoot: workspaceRoot
        )

        let timeline = try await timelineManager.createTimeline(title: "Files Test Session")
        guard let workspaceId = timeline.attachedWorkspaceIds.first,
              let workingDirectory = timeline.workingDirectory
        else {
            Issue.record("Timeline should have an attached workspace and working directory")
            return
        }

        let timelineWorkspacePath = URL(fileURLWithPath: workingDirectory)
        let noteDir = timelineWorkspacePath.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)

        let content = "# Nested Content"
        let filePath = noteDir.appendingPathComponent("TestFile.md")
        try content.write(to: filePath, atomically: true, encoding: .utf8)

        let workspaceManager = WorkspaceManager(
            repository: AgentWorkspaceService(
                workspaceRoot: workspaceRoot,
                workspacePersistence: persistence
            ),
            workspaceCreator: WorkspaceFactory()
        )
        let router = Router()
        let controller = FilesAPIController<BasicRequestContext>(workspaceManager: workspaceManager)
        controller.addRoutes(to: router.group("/workspaces/:workspaceId/files"))
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/workspaces/\(workspaceId)/files/Notes/TestFile.md", method: .get) { response in
                #expect(response.status == .ok)
                let bodyString = String(buffer: response.body)
                #expect(bodyString == content)
            }
        }
    }

    @Test("Test List Files")
    func listFiles() async throws {
        let persistence = MockPersistenceService()

        let workspaceRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        let timelineManager = TimelineManager(
            stores: .init(
                timelineStore: persistence,
                messageStore: persistence,
                workspaceStore: persistence,
                toolPersistence: persistence
            ),
            workspaceRoot: workspaceRoot
        )

        let timeline = try await timelineManager.createTimeline(title: "List Files Session")
        guard let workspaceId = timeline.attachedWorkspaceIds.first,
              let workingDirectory = timeline.workingDirectory else { return }

        let timelineWorkspacePath = URL(fileURLWithPath: workingDirectory)
        let noteDir = timelineWorkspacePath.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: noteDir, withIntermediateDirectories: true)
        try "Content".write(to: noteDir.appendingPathComponent("TestNote.md"), atomically: true, encoding: .utf8)

        let workspaceManager = WorkspaceManager(
            repository: AgentWorkspaceService(
                workspaceRoot: workspaceRoot,
                workspacePersistence: persistence
            ),
            workspaceCreator: WorkspaceFactory()
        )
        let router = Router()
        let controller = FilesAPIController<BasicRequestContext>(workspaceManager: workspaceManager)
        controller.addRoutes(to: router.group("/workspaces/:workspaceId/files"))
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/workspaces/\(workspaceId)/files", method: .get) { response in
                #expect(response.status == .ok)
                _ = try JSONDecoder().decode([String].self, from: response.body)
            }
        }
    }
}

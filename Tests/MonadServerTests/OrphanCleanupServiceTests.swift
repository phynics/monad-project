import Dependencies
import Foundation
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import Testing

@Suite final class OrphanCleanupServiceTests {
    var workspaceRoot: URL!
    var mockPersistence: MockPersistenceService!

    init() async throws {
        workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        mockPersistence = MockPersistenceService()
    }

    deinit {
        try? FileManager.default.removeItem(at: workspaceRoot)
    }

    @Test

    func cleanupOrphanedWorkspace() async throws {
        // Setup
        let orphanId = UUID()
        let orphanPath = workspaceRoot.appendingPathComponent(orphanId.uuidString).path
        try FileManager.default.createDirectory(atPath: orphanPath, withIntermediateDirectories: true)

        let activeId = UUID()
        let activePath = workspaceRoot.appendingPathComponent(activeId.uuidString).path
        try FileManager.default.createDirectory(atPath: activePath, withIntermediateDirectories: true)

        let wsOrphan = WorkspaceReference(id: orphanId, uri: .init(host: "server", path: "/orphan"), hostType: .server, rootPath: orphanPath)
        let wsActive = WorkspaceReference(id: activeId, uri: .init(host: "server", path: "/active"), hostType: .server, rootPath: activePath)

        mockPersistence.workspaces = [wsOrphan, wsActive]

        let session = Timeline(id: UUID(), title: "Test", attachedWorkspaceIds: [activeId])
        mockPersistence.timelines = [session]

        let service = OrphanCleanupService(workspaceRoot: workspaceRoot)

        // Act
        try await withDependencies {
            $0.timelinePersistence = mockPersistence
            $0.workspacePersistence = mockPersistence
            $0.memoryStore = mockPersistence
            $0.messageStore = mockPersistence
            $0.agentTemplateStore = mockPersistence
            $0.backgroundJobStore = mockPersistence
            $0.clientStore = mockPersistence
            $0.toolPersistence = mockPersistence
            $0.agentInstanceStore = mockPersistence
        } operation: {
            // Internal cleanup method is private, but run() calls it once on start.
            // We'll use Task and cancellation to run it just once.
            let task = Task {
                try await service.run()
            }
            // Give it a moment to run the initial cleanup
            try await Task.sleep(nanoseconds: 100 * 1_000_000)
            task.cancel()
        }

        // Assert
        #expect(!(FileManager.default.fileExists(atPath: orphanPath)))
        #expect(FileManager.default.fileExists(atPath: activePath))
        #expect(mockPersistence.workspaces.first { $0.id == orphanId } == nil)
        try #require(mockPersistence.workspaces.first { $0.id == activeId } != nil)
    }

    @Test

    func doNotCleanupUserManagedWorkspace() async throws {
        // Setup
        let userWsId = UUID()
        let userWsPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("UserManaged_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: userWsPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: userWsPath) }

        let wsUser = WorkspaceReference(id: userWsId, uri: .init(host: "server", path: "/user"), hostType: .server, rootPath: userWsPath)
        mockPersistence.workspaces = [wsUser]
        mockPersistence.timelines = [] // No sessions, so it is technically "orphaned"

        let service = OrphanCleanupService(workspaceRoot: workspaceRoot)

        // Act
        try await withDependencies {
            $0.timelinePersistence = mockPersistence
            $0.workspacePersistence = mockPersistence
            $0.memoryStore = mockPersistence
            $0.messageStore = mockPersistence
            $0.agentTemplateStore = mockPersistence
            $0.backgroundJobStore = mockPersistence
            $0.clientStore = mockPersistence
            $0.toolPersistence = mockPersistence
            $0.agentInstanceStore = mockPersistence
        } operation: {
            let task = Task {
                try await service.run()
            }
            try await Task.sleep(nanoseconds: 100 * 1_000_000)
            task.cancel()
        }

        // Assert
        #expect(FileManager.default.fileExists(atPath: userWsPath))
        try #require(mockPersistence.workspaces.first { $0.id == userWsId } != nil)
    }
}

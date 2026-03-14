import Dependencies
import Foundation
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import Testing

@Suite final class WorkspaceManagerTests {
    var persistence: MockPersistenceService!
    var repository: AgentWorkspaceService!
    var manager: WorkspaceManager!
    var testDir: URL!

    init() async throws {
        persistence = MockPersistenceService()
        repository = try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
        } operation: {
            AgentWorkspaceService(workspaceRoot: URL(fileURLWithPath: NSTemporaryDirectory()))
        }

        manager = WorkspaceManager(repository: repository, workspaceCreator: WorkspaceFactory())
        testDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }

    deinit {
        if let dir = testDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    @Test

    func getWorkspaceCreatesAndCaches() async throws {
        let wsId = UUID()
        let wsDir = testDir.appendingPathComponent("ws1")
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)

        let ref = WorkspaceReference(
            id: wsId,
            uri: .serverTimeline(wsId),
            hostType: .server,
            rootPath: wsDir.path
        )
        try await persistence.saveWorkspace(ref)

        // 1. Get workspace (should create via Factory and cache)
        let ws = try await manager.getWorkspace(id: wsId)
        try #require(ws != nil)
        #expect(ws?.id == wsId)

        // 2. Get again (should be from cache)
        let ws2 = try await manager.getWorkspace(id: wsId)
        #expect(ws?.id == ws2?.id)
    }

    @Test

    func getNonExistentWorkspace() async throws {
        let ws = try await manager.getWorkspace(id: UUID())
        #expect(ws == nil)
    }

    @Test

    func testCloseWorkspace() async throws {
        let wsId = UUID()
        let wsDir = testDir.appendingPathComponent("ws2")
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)

        let ref = WorkspaceReference(
            id: wsId,
            uri: .serverTimeline(wsId),
            hostType: .server,
            rootPath: wsDir.path
        )
        try await persistence.saveWorkspace(ref)

        _ = try await manager.getWorkspace(id: wsId)
        let count1 = await manager.activeWorkspaceCount
        #expect(count1 == 1)

        await manager.closeWorkspace(id: wsId)
        let count2 = await manager.activeWorkspaceCount
        #expect(count2 == 0)
    }

    @Test

    func testHealthCheckAll() async throws {
        let wsId1 = UUID()
        let wsDir = testDir.appendingPathComponent("ws3")
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)

        let ref1 = WorkspaceReference(id: wsId1, uri: .serverTimeline(wsId1), hostType: .server, rootPath: wsDir.path)
        try await persistence.saveWorkspace(ref1)

        _ = try await manager.getWorkspace(id: wsId1)

        let healthResults = await manager.healthCheckAll()
        #expect(healthResults[wsId1] ?? false)

        // Delete directory to simulate failure
        try FileManager.default.removeItem(at: wsDir)
        let healthResults2 = await manager.healthCheckAll()
        #expect(!(healthResults2[wsId1] ?? true))
    }
}

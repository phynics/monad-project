import MonadShared
import MonadCore
import XCTest
import MonadTestSupport
@testable import MonadServer
import Dependencies

final class OrphanCleanupServiceTests: XCTestCase {
    var workspaceRoot: URL!
    var mockPersistence: MockPersistenceService!

    override func setUp() async throws {
        workspaceRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        mockPersistence = MockPersistenceService()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: workspaceRoot)
    }

    func testCleanupOrphanedWorkspace() async throws {
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

        let session = Timeline(id: UUID(), title: "Test", primaryWorkspaceId: activeId)
        mockPersistence.timelines = [session]

        let service = OrphanCleanupService(workspaceRoot: workspaceRoot, persistenceService: mockPersistence)

        // Act
        try await withDependencies {
            $0.persistenceService = mockPersistence
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanPath), "Orphaned workspace directory should be deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: activePath), "Active workspace directory should be preserved")
        XCTAssertNil(mockPersistence.workspaces.first { $0.id == orphanId }, "Orphaned workspace should be removed from database")
        XCTAssertNotNil(mockPersistence.workspaces.first { $0.id == activeId }, "Active workspace should be preserved in database")
    }

    func testDoNotCleanupUserManagedWorkspace() async throws {
        // Setup
        let userWsId = UUID()
        let userWsPath = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("UserManaged_\(UUID().uuidString)").path
        try FileManager.default.createDirectory(atPath: userWsPath, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: userWsPath) }

        let wsUser = WorkspaceReference(id: userWsId, uri: .init(host: "server", path: "/user"), hostType: .server, rootPath: userWsPath)
        mockPersistence.workspaces = [wsUser]
        mockPersistence.timelines = [] // No sessions, so it is technically "orphaned"

        let service = OrphanCleanupService(workspaceRoot: workspaceRoot, persistenceService: mockPersistence)

        // Act
        try await withDependencies {
            $0.persistenceService = mockPersistence
        } operation: {
            let task = Task {
                try await service.run()
            }
            try await Task.sleep(nanoseconds: 100 * 1_000_000)
            task.cancel()
        }

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: userWsPath), "User-managed workspace should NOT be deleted from filesystem")
        XCTAssertNotNil(mockPersistence.workspaces.first { $0.id == userWsId }, "User-managed workspace should NOT be removed from database")
    }
}

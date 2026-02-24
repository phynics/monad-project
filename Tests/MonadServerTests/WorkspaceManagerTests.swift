import MonadShared
import XCTest
import Dependencies
@testable import MonadCore
@testable import MonadServer

final class WorkspaceManagerTests: XCTestCase {
    var persistence: MockPersistenceService!
    var repository: WorkspaceRepository!
    var manager: WorkspaceManager!
    var testDir: URL!
    
    override func setUp() async throws {
        persistence = MockPersistenceService()
        repository = await withDependencies {
            $0.persistenceService = persistence
        } operation: {
            WorkspaceRepository()
        }
        
        manager = WorkspaceManager(repository: repository, workspaceCreator: WorkspaceFactory())
        testDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let dir = testDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }
    
    func testGetWorkspaceCreatesAndCaches() async throws {
        let wsId = UUID()
        let wsDir = testDir.appendingPathComponent("ws1")
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)
        
        let ref = WorkspaceReference(
            id: wsId,
            uri: .serverSession(wsId),
            hostType: .server,
            rootPath: wsDir.path
        )
        try await persistence.saveWorkspace(ref)
        
        // 1. Get workspace (should create via Factory and cache)
        let ws = try await manager.getWorkspace(id: wsId)
        XCTAssertNotNil(ws)
        XCTAssertEqual(ws?.id, wsId)
        
        // 2. Get again (should be from cache)
        let ws2 = try await manager.getWorkspace(id: wsId)
        XCTAssertEqual(ws?.id, ws2?.id, "Should return cached instance or identical id")
    }
    
    func testGetNonExistentWorkspace() async throws {
        let ws = try await manager.getWorkspace(id: UUID())
        XCTAssertNil(ws)
    }
    
    func testCloseWorkspace() async throws {
        let wsId = UUID()
        let wsDir = testDir.appendingPathComponent("ws2")
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)
        
        let ref = WorkspaceReference(
            id: wsId,
            uri: .serverSession(wsId),
            hostType: .server,
            rootPath: wsDir.path
        )
        try await persistence.saveWorkspace(ref)
        
        _ = try await manager.getWorkspace(id: wsId)
        let count1 = await manager.activeWorkspaceCount
        XCTAssertEqual(count1, 1)
        
        await manager.closeWorkspace(id: wsId)
        let count2 = await manager.activeWorkspaceCount
        XCTAssertEqual(count2, 0)
    }
    
    func testHealthCheckAll() async throws {
        let wsId1 = UUID()
        let wsDir = testDir.appendingPathComponent("ws3")
        try FileManager.default.createDirectory(at: wsDir, withIntermediateDirectories: true)
        
        let ref1 = WorkspaceReference(id: wsId1, uri: .serverSession(wsId1), hostType: .server, rootPath: wsDir.path)
        try await persistence.saveWorkspace(ref1)
        
        _ = try await manager.getWorkspace(id: wsId1)
        
        let healthResults = await manager.healthCheckAll()
        XCTAssertTrue(healthResults[wsId1] ?? false)
        
        // Delete directory to simulate failure
        try FileManager.default.removeItem(at: wsDir)
        let healthResults2 = await manager.healthCheckAll()
        XCTAssertFalse(healthResults2[wsId1] ?? true)
    }
}
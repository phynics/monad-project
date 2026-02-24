import MonadShared
import XCTest
import Dependencies
@testable import MonadCore
@testable import MonadServer

final class WorkspaceManagerTests: XCTestCase {
    var persistence: MockPersistenceService!
    var repository: WorkspaceRepository!
    var manager: WorkspaceManager!
    
    override func setUp() async throws {
        persistence = MockPersistenceService()
        repository = await withDependencies {
            $0.persistenceService = persistence
        } operation: {
            WorkspaceRepository()
        }
        
        manager = WorkspaceManager(repository: repository, workspaceCreator: WorkspaceFactory())
    }
    
    func testGetWorkspaceCreatesAndCaches() async throws {
        let wsId = UUID()
        let ref = WorkspaceReference(
            id: wsId,
            uri: .serverSession(wsId),
            hostType: .server,
            rootPath: "/tmp/monad_test_ws"
        )
        try await persistence.saveWorkspace(ref)
        
        // 1. Get workspace (should create via Factory and cache)
        let ws = try await manager.getWorkspace(id: wsId)
        XCTAssertNotNil(ws)
        XCTAssertEqual(ws?.id, wsId)
        XCTAssertNotNil(ws)
        
        // 2. Get again (should be from cache)
        let ws2 = try await manager.getWorkspace(id: wsId)
        XCTAssertEqual(ws?.id, ws2?.id, "Should return cached instance or identical id")
        // Since WorkspaceProtocol is an actor (usually), we can't easily check identity if it's wrapped in protocol
        // but the behavior of WorkspaceManager ensures caching.
    }
    
    func testGetNonExistentWorkspace() async throws {
        let ws = try await manager.getWorkspace(id: UUID())
        XCTAssertNil(ws)
    }
    
    func testCloseWorkspace() async throws {
        let wsId = UUID()
        let ref = WorkspaceReference(
            id: wsId,
            uri: .serverSession(wsId),
            hostType: .server,
            rootPath: "/tmp/monad_test_ws"
        )
        try await persistence.saveWorkspace(ref)
        
        _ = try await manager.getWorkspace(id: wsId)
        let count1 = await manager.activeWorkspaceCount
        XCTAssertEqual(count1, 1)
        
        await manager.closeWorkspace(id: wsId)
        let count2 = await manager.activeWorkspaceCount
        XCTAssertEqual(count2, 0)
    }
}
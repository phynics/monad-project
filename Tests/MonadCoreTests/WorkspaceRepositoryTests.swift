import XCTest
import Dependencies
@testable import MonadCore

final class WorkspaceRepositoryTests: XCTestCase {
    var persistence: MockPersistenceService!
    var repository: WorkspaceRepository!

    override func setUp() async throws {
        persistence = MockPersistenceService()
        repository = await withDependencies {
            $0.persistenceService = persistence
        } operation: {
            WorkspaceRepository()
        }
    }

    func testCreateWorkspace() async throws {
        let uri = WorkspaceURI(host: "monad-server", path: "/test")
        let metadata: [String: AnyCodable] = ["key": .string("value")]

        let ws = try await repository.createWorkspace(
            uri: uri,
            hostType: .server,
            rootPath: "/tmp/ws",
            metadata: metadata
        )

        XCTAssertEqual(ws.uri, uri)
        XCTAssertEqual(ws.rootPath, "/tmp/ws")
        XCTAssertEqual(ws.metadata["key"]?.asString, "value")

        // Verify it was saved to persistence
        let saved = try await persistence.fetchWorkspace(id: ws.id)
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.metadata["key"]?.asString, "value")
    }

    func testGetWorkspace() async throws {
        let ws = WorkspaceReference(
            uri: .serverSession(UUID()),
            hostType: .server,
            rootPath: "/path",
            metadata: ["test": .boolean(true)]
        )
        try await persistence.saveWorkspace(ws)

        let retrieved = try await repository.getWorkspace(id: ws.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, ws.id)
        XCTAssertEqual(retrieved?.metadata["test"]?.asString, nil) // AnyCodable comparison
        XCTAssertEqual(retrieved?.metadata["test"]?.value as? Bool, true)
    }

    func testListWorkspaces() async throws {
        let ws1 = WorkspaceReference(uri: .serverSession(UUID()), hostType: .server)
        let ws2 = WorkspaceReference(uri: .serverSession(UUID()), hostType: .server)
        try await persistence.saveWorkspace(ws1)
        try await persistence.saveWorkspace(ws2)

        let list = try await repository.listWorkspaces()
        XCTAssertEqual(list.count, 2)
        XCTAssertTrue(list.contains(where: { $0.id == ws1.id }))
        XCTAssertTrue(list.contains(where: { $0.id == ws2.id }))
    }

    func testDeleteWorkspace() async throws {
        let ws = WorkspaceReference(uri: .serverSession(UUID()), hostType: .server)
        try await persistence.saveWorkspace(ws)

        try await repository.deleteWorkspace(id: ws.id)
        let retrieved = try await persistence.fetchWorkspace(id: ws.id)
        XCTAssertNil(retrieved)
    }

    func testUpdateWorkspace() async throws {
        var ws = WorkspaceReference(uri: .serverSession(UUID()), hostType: .server)
        try await persistence.saveWorkspace(ws)

        ws.status = .missing
        try await repository.updateWorkspace(ws)

        let retrieved = try await persistence.fetchWorkspace(id: ws.id)
        XCTAssertEqual(retrieved?.status, .missing)
    }
}

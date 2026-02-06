import XCTest
@testable import MonadCLI

final class LocalConfigManagerTests: XCTestCase {
    var tempFileURL: URL!
    var manager: LocalConfigManager!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        manager = LocalConfigManager(storageURL: tempFileURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    func testPersistence() {
        var config = manager.getConfig()
        XCTAssertNil(config.lastSessionId)
        XCTAssertNil(config.clientWorkspaces)

        let sessionId = UUID().uuidString
        let workspaces = ["file:///tmp/test": UUID().uuidString]

        manager.updateLastSessionId(sessionId)
        manager.updateClientWorkspaces(workspaces)

        let savedConfig = manager.getConfig()
        XCTAssertEqual(savedConfig.lastSessionId, sessionId)
        XCTAssertEqual(savedConfig.clientWorkspaces, workspaces)
    }
}

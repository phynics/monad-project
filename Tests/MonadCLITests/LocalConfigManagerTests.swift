import Testing
import Foundation
@testable import MonadCLI

@Suite final class LocalConfigManagerTests {
    var tempFileURL: URL!
    var manager: LocalConfigManager!

    init() {
        // super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        manager = LocalConfigManager(storageURL: tempFileURL)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempFileURL)
        // super.tearDown()
    }

    @Test

    func testPersistence() {
        let config = manager.getConfig()
        #expect(config.lastSessionId == nil)
        #expect(config.clientWorkspaces == nil)

        let timelineId = UUID().uuidString
        let workspaces = ["file:///tmp/test": UUID().uuidString]

        manager.updateLastSessionId(timelineId)
        manager.updateClientWorkspaces(workspaces)

        let savedConfig = manager.getConfig()
        #expect(savedConfig.lastSessionId == timelineId)
        #expect(savedConfig.clientWorkspaces == workspaces)
    }
}

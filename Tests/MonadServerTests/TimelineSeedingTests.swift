import Dependencies
import Foundation
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import Testing

@Suite final class SessionSeedingTests {
    var persistence: MockPersistenceService!
    var workspaceRoot: URL!

    init() async throws {
        persistence = MockPersistenceService()
        workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
    }

    @Test

    func sessionSeeding() async throws {
        let persistence = try #require(persistence)
        let workspaceRoot = try #require(workspaceRoot)
        try await TestDependencies()
            .withMocks(persistence: persistence)
            .run {
                let timelineManager = TimelineManager(workspaceRoot: workspaceRoot)

                let session = try await timelineManager.createTimeline(title: "Test Session")

                let sessionDir = workspaceRoot.appendingPathComponent("timelines").appendingPathComponent(session.id.uuidString)
                let notesDir = sessionDir.appendingPathComponent("Notes")
                #expect(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Welcome.md").path))
                #expect(FileManager.default.fileExists(atPath: notesDir.appendingPathComponent("Project.md").path))
            }
    }
}

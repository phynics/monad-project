import Dependencies
import Foundation
@testable import MonadCore
@testable import MonadShared
import MonadTestSupport
import Testing

// MARK: - Test Fixture

/// Sets up a TimelineManager with in-memory persistence and a workspace already seeded.
private struct AttachmentFixture {
    let manager: TimelineManager
    let persistence: MockPersistenceService
    let workspaceRoot: URL

    /// Saved workspace references — pre-seeded into persistence before tests run.
    let serverWS: WorkspaceReference
    let clientWS: WorkspaceReference
    let extraWS: WorkspaceReference

    static func make() async throws -> Self {
        let persistence = MockPersistenceService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        let serverWS = WorkspaceReference(
            uri: WorkspaceURI(host: "monad-server", path: "/agent/primary"),
            hostType: .server,
            rootPath: workspaceRoot.appendingPathComponent("primary").path
        )
        let clientWS = WorkspaceReference(
            uri: WorkspaceURI(host: "user-mac", path: "/projects/app"),
            hostType: .client
        )
        let extraWS = WorkspaceReference(
            uri: WorkspaceURI(host: "user-mac", path: "/projects/lib"),
            hostType: .client
        )

        try await persistence.saveWorkspace(serverWS)
        try await persistence.saveWorkspace(clientWS)
        try await persistence.saveWorkspace(extraWS)

        return Self(
            manager: TimelineManager(workspaceRoot: workspaceRoot),
            persistence: persistence,
            workspaceRoot: workspaceRoot,
            serverWS: serverWS,
            clientWS: clientWS,
            extraWS: extraWS
        )
    }
}

private func withFixture(
    _ body: @Sendable (AttachmentFixture) async throws -> Void
) async throws {
    let fixture = try await AttachmentFixture.make()
    try await withDependencies {
        $0.timelinePersistence = fixture.persistence
        $0.workspacePersistence = fixture.persistence
        $0.memoryStore = fixture.persistence
        $0.messageStore = fixture.persistence
        $0.agentTemplateStore = fixture.persistence
        $0.backgroundJobStore = fixture.persistence
        $0.clientStore = fixture.persistence
        $0.toolPersistence = fixture.persistence
        $0.agentInstanceStore = fixture.persistence
        $0.embeddingService = MockEmbeddingService()
        $0.llmService = MockLLMService()
    } operation: {
        try await body(fixture)
    }
}

// MARK: - Timeline.attachedWorkspaces (model)

@Suite("Timeline.attachedWorkspaces")
struct TimelineAttachedWorkspacesTests {
    @Test("defaults to empty array")
    func defaultsEmpty() {
        let timeline = Timeline()
        #expect(timeline.attachedWorkspaces.isEmpty)
    }

    @Test("round-trips single UUID through JSON encoding")
    func singleUUID() {
        let id = UUID()
        let timeline = Timeline(attachedWorkspaceIds: [id])
        #expect(timeline.attachedWorkspaces == [id])
    }

    @Test("round-trips multiple UUIDs preserving order")
    func multipleUUIDs() {
        let ids = [UUID(), UUID(), UUID()]
        let timeline = Timeline(attachedWorkspaceIds: ids)
        #expect(timeline.attachedWorkspaces == ids)
    }

    @Test("malformed JSON falls back to empty array")
    func malformedJSON() {
        var timeline = Timeline()
        timeline.attachedWorkspaceIds = "not-valid-json"
        #expect(timeline.attachedWorkspaces.isEmpty)
    }
}

// MARK: - attachWorkspace

@Suite("TimelineManager.attachWorkspace")
struct AttachWorkspaceTests {
    @Test("attaching non-primary adds to attachedWorkspaces")
    func attachNonPrimary() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let attached = workspaces?.attached ?? []
            #expect(attached.contains { $0.id == fix.clientWS.id })
            #expect(workspaces?.primary?.id != fix.clientWS.id)
        }
    }

    @Test("attaching as primary sets primaryWorkspaceId")
    func attachAsPrimary() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: true)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces?.primary?.id == fix.clientWS.id)
        }
    }

    @Test("attaching as primary does not also add to attached list")
    func primaryNotDuplicated() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: true)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let attached = workspaces?.attached ?? []
            #expect(!attached.contains { $0.id == fix.clientWS.id }, "Primary workspace must not appear in attached list")
        }
    }

    @Test("attaching same non-primary workspace twice does not duplicate")
    func noDuplicateAttach() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let matching = (workspaces?.attached ?? []).filter { $0.id == fix.clientWS.id }
            #expect(matching.count == 1)
        }
    }

    @Test("attaching a workspace already set as primary as non-primary is a no-op")
    func attachPrimaryAsNonPrimaryIsNoOp() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: true)
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            // Should still be primary, not moved to attached
            #expect(workspaces?.primary?.id == fix.clientWS.id)
            let attached = workspaces?.attached ?? []
            #expect(!attached.contains { $0.id == fix.clientWS.id })
        }
    }

    @Test("multiple distinct workspaces can be attached")
    func multipleAttached() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)
            try await fix.manager.attachWorkspace(fix.extraWS.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let attached = workspaces?.attached ?? []
            #expect(attached.contains { $0.id == fix.clientWS.id })
            #expect(attached.contains { $0.id == fix.extraWS.id })
            #expect(attached.count >= 2)
        }
    }

    @Test("attach persists across a fresh manager reading from DB")
    func attachPersistsToDB() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)

            // New manager, same persistence — simulates server restart
            let freshManager = TimelineManager(workspaceRoot: fix.workspaceRoot)
            let workspaces = await freshManager.getWorkspaces(for: timeline.id)
            let attached = workspaces?.attached ?? []
            #expect(attached.contains { $0.id == fix.clientWS.id })
        }
    }

    @Test("attaching to unknown timeline throws")
    func unknownTimelineThrows() async throws {
        try await withFixture { fix in
            await #expect(throws: (any Error).self) {
                try await fix.manager.attachWorkspace(fix.clientWS.id, to: UUID(), isPrimary: false)
            }
        }
    }
}

// MARK: - detachWorkspace

@Suite("TimelineManager.detachWorkspace")
struct DetachWorkspaceTests {
    @Test("detaching an attached workspace removes it from the list")
    func detachAttached() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)

            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let attached = workspaces?.attached ?? []
            #expect(!attached.contains { $0.id == fix.clientWS.id })
        }
    }

    @Test("detaching primary workspace clears primaryWorkspaceId")
    func detachPrimary() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: true)

            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces?.primary == nil)
        }
    }

    @Test("detaching workspace not in list does not throw")
    func detachUnknownIsNoOp() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            // Should not throw
            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces?.attached.isEmpty == true || workspaces?.attached != nil)
        }
    }

    @Test("detaching one workspace leaves others intact")
    func detachLeavesOthers() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)
            try await fix.manager.attachWorkspace(fix.extraWS.id, to: timeline.id, isPrimary: false)

            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let attached = workspaces?.attached ?? []
            #expect(!attached.contains { $0.id == fix.clientWS.id })
            #expect(attached.contains { $0.id == fix.extraWS.id })
        }
    }

    @Test("detach persists across a fresh manager reading from DB")
    func detachPersistsToDB() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)
            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)

            let freshManager = TimelineManager(workspaceRoot: fix.workspaceRoot)
            let workspaces = await freshManager.getWorkspaces(for: timeline.id)
            let attached = workspaces?.attached ?? []
            #expect(!attached.contains { $0.id == fix.clientWS.id })
        }
    }

    @Test("detaching from unknown timeline throws")
    func unknownTimelineThrows() async throws {
        try await withFixture { fix in
            await #expect(throws: (any Error).self) {
                try await fix.manager.detachWorkspace(fix.clientWS.id, from: UUID())
            }
        }
    }
}

// MARK: - getWorkspaces

@Suite("TimelineManager.getWorkspaces")
struct GetWorkspacesTests {
    @Test("returns nil for unknown timeline")
    func nilForUnknown() async throws {
        try await withFixture { fix in
            let result = await fix.manager.getWorkspaces(for: UUID())
            #expect(result == nil)
        }
    }

    @Test("returns nil primary and empty attached when nothing is attached")
    func emptyAfterCreate() async throws {
        try await withFixture { fix in
            // Create a timeline without a primary workspace
            var timeline = Timeline()
            try await fix.persistence.saveTimeline(timeline)
            // Remove primary workspace set by createTimeline by saving a bare timeline
            _ = timeline // just for clarity

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces != nil)
            #expect(workspaces?.primary == nil)
            #expect(workspaces?.attached.isEmpty == true)
        }
    }

    @Test("reflects attach then detach in sequence")
    func attachThenDetach() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)
            let afterAttach = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(afterAttach?.attached.contains { $0.id == fix.clientWS.id } == true)

            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)
            let afterDetach = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(afterDetach?.attached.contains { $0.id == fix.clientWS.id } == false)
        }
    }

    @Test("server workspace with missing rootPath is marked .missing")
    func serverMissingPath() async throws {
        try await withFixture { fix in
            // serverWS has rootPath pointing to a non-existent directory
            let missingWS = WorkspaceReference(
                uri: WorkspaceURI(host: "monad-server", path: "/agent/gone"),
                hostType: .server,
                rootPath: "/tmp/monad-test-definitely-does-not-exist-\(UUID().uuidString)"
            )
            try await fix.persistence.saveWorkspace(missingWS)

            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(missingWS.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let ws = workspaces?.attached.first { $0.id == missingWS.id }
            #expect(ws?.status == .missing)
        }
    }

    @Test("client workspace with missing rootPath is NOT marked .missing")
    func clientMissingPathIgnored() async throws {
        try await withFixture { fix in
            let clientWithPath = WorkspaceReference(
                uri: WorkspaceURI(host: "user-mac", path: "/projects/gone"),
                hostType: .client,
                rootPath: "/tmp/monad-test-definitely-does-not-exist-\(UUID().uuidString)"
            )
            try await fix.persistence.saveWorkspace(clientWithPath)

            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(clientWithPath.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let ws = workspaces?.attached.first { $0.id == clientWithPath.id }
            #expect(ws?.status != .missing, "Client workspace paths are not validated server-side")
        }
    }

    @Test("server workspace with existing path stays .active")
    func serverExistingPathActive() async throws {
        try await withFixture { fix in
            let existingDir = fix.workspaceRoot.appendingPathComponent("present-ws")
            try FileManager.default.createDirectory(at: existingDir, withIntermediateDirectories: true)

            let ws = WorkspaceReference(
                uri: WorkspaceURI(host: "monad-server", path: "/agent/present"),
                hostType: .server,
                rootPath: existingDir.path
            )
            try await fix.persistence.saveWorkspace(ws)

            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(ws.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            let found = workspaces?.attached.first { $0.id == ws.id }
            #expect(found?.status == .active)
        }
    }

    @Test("workspace with nil rootPath is not marked missing regardless of hostType")
    func nilRootPathNotMissing() async throws {
        try await withFixture { fix in
            let wsNoPath = WorkspaceReference(
                uri: WorkspaceURI(host: "monad-server", path: "/agent/no-path"),
                hostType: .server,
                rootPath: nil
            )
            try await fix.persistence.saveWorkspace(wsNoPath)

            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(wsNoPath.id, to: timeline.id, isPrimary: true)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces?.primary?.status != .missing)
        }
    }
}

// MARK: - Attach/Detach round-trip

@Suite("Workspace attach/detach round-trip")
struct WorkspaceRoundTripTests {
    @Test("replacing primary by attaching a new one as primary")
    func replacePrimary() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.serverWS.id, to: timeline.id, isPrimary: true)
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: true)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces?.primary?.id == fix.clientWS.id, "New primary should replace old")
        }
    }

    @Test("detaching all workspaces leaves timeline with no primary and no attached")
    func detachAll() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()
            try await fix.manager.attachWorkspace(fix.serverWS.id, to: timeline.id, isPrimary: true)
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)
            try await fix.manager.attachWorkspace(fix.extraWS.id, to: timeline.id, isPrimary: false)

            try await fix.manager.detachWorkspace(fix.serverWS.id, from: timeline.id)
            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)
            try await fix.manager.detachWorkspace(fix.extraWS.id, from: timeline.id)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces?.primary == nil)
            #expect(workspaces?.attached.isEmpty == true)
        }
    }

    @Test("re-attaching a previously detached workspace works")
    func reattach() async throws {
        try await withFixture { fix in
            let timeline = try await fix.manager.createTimeline()

            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)
            try await fix.manager.detachWorkspace(fix.clientWS.id, from: timeline.id)
            try await fix.manager.attachWorkspace(fix.clientWS.id, to: timeline.id, isPrimary: false)

            let workspaces = await fix.manager.getWorkspaces(for: timeline.id)
            #expect(workspaces?.attached.contains { $0.id == fix.clientWS.id } == true)
        }
    }
}

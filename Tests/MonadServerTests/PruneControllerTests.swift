import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import Testing

@Suite(.serialized)
@MainActor
struct PruneControllerTests {
    private let persistence: PersistenceService

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        persistence = PersistenceService(dbQueue: queue)
    }

    private func makeApp() -> some ApplicationProtocol {
        return withDependencies {
            $0.memoryStore = persistence.memoryStore
            $0.timelinePersistence = persistence.timelineStore
            $0.messageStore = persistence.messageStore
        } operation: {
            let router = Router()
            let controller = PruneAPIController<BasicRequestContext>()
            controller.addRoutes(to: router.group("/prune"))
            return Application(router: router)
        }
    }

    // MARK: - pruneMemories

    @Test("POST /prune/memories with query returns count and dryRun flag")
    func pruneMemories_byQuery_returnsPruneResponse() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(PruneMemoriesRequest(query: "old topic", days: nil, dryRun: true))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/prune/memories",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(PruneResponse.self, from: response.body)
                #expect(result.count == 0)
                #expect(result.dryRun == true)
            }
        }
    }

    @Test("POST /prune/memories with days returns count and dryRun flag")
    func pruneMemories_byDays_returnsPruneResponse() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(PruneMemoriesRequest(query: nil, days: 30, dryRun: false))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/prune/memories",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(PruneResponse.self, from: response.body)
                #expect(result.dryRun == false)
            }
        }
    }

    @Test("POST /prune/memories with neither query nor days returns count 0")
    func pruneMemories_noParams_returnsZeroCount() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(PruneMemoriesRequest(query: nil, days: nil, dryRun: false))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/prune/memories",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(PruneResponse.self, from: response.body)
                #expect(result.count == 0)
            }
        }
    }

    // MARK: - pruneTimelines

    @Test("POST /prune/sessions returns 0 count on empty database")
    func pruneTimelines_emptyDatabase_returnsZero() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(PruneTimelineRequest(days: 30, excludedTimelineIds: [], dryRun: true))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/prune/sessions",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(PruneResponse.self, from: response.body)
                #expect(result.count == 0)
                #expect(result.dryRun == true)
            }
        }
    }

    @Test("POST /prune/sessions prunes old sessions")
    func pruneTimelines_prunesOldSessions() async throws {
        // Insert an old non-archived session
        var oldSession = Timeline(title: "Old Session")
        oldSession.updatedAt = Date().addingTimeInterval(-60 * 24 * 60 * 60) // 60 days ago
        try await persistence.saveTimeline(oldSession)

        let app = makeApp()
        let body = try JSONEncoder().encode(PruneTimelineRequest(days: 30, excludedTimelineIds: [], dryRun: false))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/prune/sessions",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(PruneResponse.self, from: response.body)
                #expect(result.count >= 1)
            }
        }
    }

    @Test("POST /prune/sessions excludes specified session IDs")
    func pruneTimelines_excludesSpecifiedIds() async throws {
        var oldSession = Timeline(title: "Excluded Session")
        oldSession.updatedAt = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try await persistence.saveTimeline(oldSession)

        let app = makeApp()
        let body = try JSONEncoder().encode(PruneTimelineRequest(days: 30, excludedTimelineIds: [oldSession.id], dryRun: false))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/prune/sessions",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(PruneResponse.self, from: response.body)
                #expect(result.count == 0)
            }
        }
    }

    // MARK: - pruneMessages

    @Test("POST /prune/messages returns 0 count on empty database")
    func pruneMessages_emptyDatabase_returnsZero() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(PruneMessagesRequest(days: 30, dryRun: true))

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/prune/messages",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .ok)
                let result = try JSONDecoder().decode(PruneResponse.self, from: response.body)
                #expect(result.count == 0)
                #expect(result.dryRun == true)
            }
        }
    }
}

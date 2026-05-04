import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import PositronicKit
@testable import MonadServer
import PKShared
import MonadShared
import PKTestSupport
import Testing

@Suite struct SessionControllerTests {
    @Test("Test Create Session Endpoint")
    func createSession() async throws {
        let workspace = TestWorkspace()

        try await TestDependencies()
            .withMocks()
            .withTimelineManager(workspaceRoot: workspace.root)
            .run {
                let router = Router()
                let controller = TimelineAPIController<BasicRequestContext>()
                controller.addRoutes(to: router.group("/sessions"))
                let app = Application(router: router)

                try await app.test(.router) { client in
                    try await client.execute(uri: "/sessions", method: .post) { response in
                        #expect(response.status == .created)

                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let session = try decoder.decode(TimelineResponse.self, from: response.body)
                        #expect(session.id.uuidString.isEmpty == false)
                    }
                }
            }
    }

    @Test("list sessions excludes private timelines")
    func listSessions_excludesPrivateTimelines() async throws {
        let persistence = MockPersistenceService()

        try await persistence.saveTimeline(Timeline(title: "Public Timeline"))
        try await persistence.saveTimeline(Timeline(title: "Private Timeline", isPrivate: true))

        try await TestDependencies()
            .withMocks(persistence: persistence)
            .withTimelineManager(workspaceRoot: TestWorkspace().root)
            .run {
                let router = Router()
                let controller = TimelineAPIController<BasicRequestContext>()
                controller.addRoutes(to: router.group("/sessions"))
                let app = Application(router: router)

                try await app.test(.router) { client in
                    try await client.execute(uri: "/sessions", method: .get) { response in
                        #expect(response.status == .ok)

                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let sessions = try decoder.decode(
                            PaginatedResponse<TimelineResponse>.self,
                            from: response.body
                        )

                        #expect(sessions.items.count == 1)
                        #expect(sessions.items.first?.title == "Public Timeline")
                    }
                }
            }
    }

    @Test("delete private session is rejected")
    func deleteSession_privateTimelineRejected() async throws {
        let persistence = MockPersistenceService()
        let privateTimeline = Timeline(title: "Private Timeline", isPrivate: true)
        try await persistence.saveTimeline(privateTimeline)

        try await TestDependencies()
            .withMocks(persistence: persistence)
            .withTimelineManager(workspaceRoot: TestWorkspace().root)
            .run {
                let router = Router()
                router.add(middleware: ErrorMiddleware())
                let controller = TimelineAPIController<BasicRequestContext>()
                controller.addRoutes(to: router.group("/sessions"))
                let app = Application(router: router)

                try await app.test(.router) { client in
                    try await client.execute(
                        uri: "/sessions/\(privateTimeline.id.uuidString)",
                        method: .delete
                    ) { response in
                        #expect(response.status == .forbidden)
                    }
                }
            }
    }
}

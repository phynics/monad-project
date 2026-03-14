import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
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
}

import Foundation
import Hummingbird
import HummingbirdTesting
import PositronicKit
@testable import MonadServer
import PKShared
import PKTestSupport
import NIOCore
import Testing

@Suite struct AgentInstanceControllerTests {
    @Test("create agent validation errors return 422")
    func createAgent_validationErrorReturns422() async throws {
        let persistence = MockPersistenceService()
        let workspace = TestWorkspace()

        try await TestDependencies()
            .withMocks(persistence: persistence)
            .withOrchestration(workspaceRoot: workspace.root)
            .run { _ in
                let agentInstanceManager = AgentInstanceManager(
                    repository: AgentWorkspaceService(workspaceRoot: workspace.root)
                )

                let router = Router()
                router.add(middleware: ErrorMiddleware())
                AgentInstanceAPIController<BasicRequestContext>(
                    agentInstanceManager: agentInstanceManager
                )
                .addRoutes(to: router.group("/agents"))
                let app = Application(router: router)

                let encoded = try JSONEncoder().encode([
                    "name": "Assistant",
                    "description": "",
                ])
                let body = ByteBuffer(data: encoded)

                try await app.test(.router) { client in
                    try await client.execute(uri: "/agents", method: .post, body: body) { response in
                        #expect(response.status == .unprocessableContent)
                    }
                }
            }
    }
}

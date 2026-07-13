import Foundation
import Hummingbird
import HummingbirdTesting
@testable import MonadServerCore
import NIOCore
import PKShared
import PKTestSupport
import PositronicKit
import Testing

struct AgentInstanceControllerTests {
    @Test("create agent validation errors return 422")
    func createAgent_validationErrorReturns422() async throws {
        let workspace = TestWorkspace()

        let agentInstanceManager = AgentInstanceManager(
            repository: DefaultWorkspaceCatalog(workspaceRoot: workspace.root)
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

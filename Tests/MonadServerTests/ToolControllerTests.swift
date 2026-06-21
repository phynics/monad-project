import Foundation
import Hummingbird
import HummingbirdTesting
@testable import MonadServer
import MonadShared
import NIOCore
import PKShared
import PKTestSupport
import PositronicKit
import Testing

struct ToolControllerTests {
    @Test("Test Tools API")
    func toolsAPI() async throws {
        let workspace = TestWorkspace()

        let runtime = TestRuntime(workspaceRoot: workspace.root)
        let timelineManager = runtime.timelineManager
        let toolRouter = runtime.toolRouter
        let persistence = runtime.persistence

        let router = Router()
        router.add(middleware: ErrorMiddleware())
        let controller = ToolAPIController<BasicRequestContext>(
            timelineManager: timelineManager,
            timelineStore: persistence,
            messageStore: persistence,
            toolRouter: toolRouter
        )
        controller.addRoutes(to: router.group("/tools"))

        let app = Application(router: router)

        try await app.test(.router) { client in
            let session = try await timelineManager.createTimeline()

            // 1. List
            try await client.execute(uri: "/tools/\(session.id)", method: .get) { response in
                #expect(response.status == .ok)
                let tools = try JSONDecoder().decode([ToolInfo].self, from: response.body)
                #expect(tools.count >= 0)
            }

            // 2. Execute (Mock execution)
            let execReq = ExecuteToolRequest(timelineId: session.id, name: "test_tool", arguments: [:])
            let execBuffer = try ByteBuffer(bytes: JSONEncoder().encode(execReq))

            try await client.execute(uri: "/tools/execute", method: .post, body: execBuffer) { response in
                #expect(response.status == .notFound)
            }

            // 3. List Global (Without Session)
            try await client.execute(uri: "/tools", method: .get) { response in
                #expect(response.status == .ok)
                let tools = try JSONDecoder().decode([ToolInfo].self, from: response.body)
                #expect(tools.count >= 0)
            }
        }
    }
}

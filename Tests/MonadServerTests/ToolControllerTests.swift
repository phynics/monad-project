import MonadShared
import MonadCore
import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
import MonadTestSupport
@testable import MonadServer
import NIOCore
import Dependencies

@Suite struct ToolControllerTests {

    @Test("Test Tools API")
    func testToolsAPI() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        let timelineManager = TimelineManager(
            workspaceRoot: workspaceRoot
        )
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.msAgentRegistry = MSAgentRegistry()
            $0.timelineManager = timelineManager
        } operation: {
            let toolRouter = ToolRouter()
            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let controller = ToolAPIController<BasicRequestContext>(timelineManager: timelineManager, toolRouter: toolRouter)
            controller.addRoutes(to: router.group("/tools"))

            let app = Application(router: router)

            try await app.test(.router) { client in
                // Create Session
                let session = try await timelineManager.createTimeline()

                // 1. List
                try await client.execute(uri: "/tools/\(session.id)", method: .get) { response in
                    #expect(response.status == .ok)
                    let tools = try JSONDecoder().decode([ToolInfo].self, from: response.body)
                    #expect(tools.count >= 0)
                }

                // 2. Execute (Mock execution)
                let execReq = ExecuteToolRequest(timelineId: session.id, name: "test_tool", arguments: [:])
                let execBuffer = ByteBuffer(bytes: try JSONEncoder().encode(execReq))

                try await client.execute(uri: "/tools/execute", method: .post, body: execBuffer) { response in
                    // Should return not found because 'test_tool' is not in session
                    #expect(response.status == .notFound)
                }

                // 3. List Global (Without Session)
                try await client.execute(uri: "/tools", method: .get) { response in
                    #expect(response.status == .ok)
                    let tools = try JSONDecoder().decode([ToolInfo].self, from: response.body)
                    // The system tools should be returned dynamically based on registry registration
                    #expect(tools.count >= 0)
                }
            }
        }
    }
}

import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer
import MonadCore
import NIOCore
import Dependencies

@Suite struct ToolControllerTests {

    @Test("Test Tools API")
    func testToolsAPI() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        let sessionManager = SessionManager(
            workspaceRoot: workspaceRoot
        )
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
            $0.sessionManager = sessionManager
        } operation: {
            let toolRouter = ToolRouter()
            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let controller = ToolAPIController<BasicRequestContext>(sessionManager: sessionManager, toolRouter: toolRouter)
            controller.addRoutes(to: router.group("/tools"))
    
            let app = Application(router: router)
    
            try await app.test(.router) { client in
                // Create Session
                let session = try await sessionManager.createSession()
    
                // 1. List
                try await client.execute(uri: "/tools/\(session.id)", method: .get) { response in
                    #expect(response.status == .ok)
                    let tools = try JSONDecoder().decode([ToolInfo].self, from: response.body)
                    #expect(tools.count >= 0)
                }
    
                // 2. Execute (Mock execution)
                let execReq = ExecuteToolRequest(sessionId: session.id, name: "test_tool", arguments: [:])
                let execBuffer = ByteBuffer(bytes: try JSONEncoder().encode(execReq))
    
                try await client.execute(uri: "/tools/execute", method: .post, body: execBuffer) { response in
                    // Should return not found because 'test_tool' is not in session
                    #expect(response.status == .notFound)
                }
            }
        }
    }
}

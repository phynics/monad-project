import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer
import MonadCore
import Dependencies

@Suite struct SessionControllerTests {

    @Test("Test Create Session Endpoint")
    func testCreateSession() async throws {
        // Setup deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
            
            // Setup App
            let router = Router()
            let controller = SessionAPIController<BasicRequestContext>(sessionManager: sessionManager)
            controller.addRoutes(to: router.group("/sessions"))
    
            let app = Application(router: router)
            
            // Test
            try await app.test(.router) { client in
                try await client.execute(uri: "/sessions", method: .post) { response in
                    #expect(response.status == .created)
                    
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let session = try decoder.decode(SessionResponse.self, from: response.body)
                    #expect(session.id.uuidString.isEmpty == false)
                }
            }
        }
    }
}

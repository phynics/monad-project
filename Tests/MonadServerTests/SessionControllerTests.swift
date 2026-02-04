import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServerCore
import MonadCore

@Suite struct SessionControllerTests {
    
    @Test("Test Create Session Endpoint")
    func testCreateSession() async throws {
        // Setup deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding, llmService: llm)
        
        // Setup App
        let router = Router()
        let controller = SessionController<BasicRequestContext>(sessionManager: sessionManager)
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

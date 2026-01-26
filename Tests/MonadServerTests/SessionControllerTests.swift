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
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding)
        
        // Setup App
        let router = Router()
        let controller = SessionController<BasicRequestContext>(sessionManager: sessionManager)
        controller.addRoutes(to: router.group("/sessions"))
        
        let app = Application(router: router)
        
        // Test
        try await app.test(.router) { client in
            try await client.execute(uri: "/sessions", method: .post) { response in
                #expect(response.status == .created)
                
                let session = try JSONDecoder().decode(Session.self, from: response.body)
                #expect(session.id.uuidString.isEmpty == false)
            }
        }
    }
}

import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer
import MonadCore
import NIOCore

@Suite struct StatusControllerTests {
    @Test("Test Status Endpoint")
    func testStatusEndpoint() async throws {
        let persistence = MockPersistenceService()
        let llmService = MockLLMService()
        
        let router = Router()
        let controller = StatusAPIController<BasicRequestContext>(
            persistenceService: persistence,
            llmService: llmService,
            startTime: Date()
        )
        controller.addRoutes(to: router)
        
        let app = Application(router: router)
        
        try await app.test(.router) { client in
            try await client.execute(uri: "/status", method: .get) { response in
                #expect(response.status == .ok)
                
                let statusResponse = try JSONDecoder().decode(StatusResponse.self, from: response.body)
                #expect(statusResponse.status == .ok)
                #expect(statusResponse.components["database"]?.status == .ok)
                #expect(statusResponse.components["ai_provider"]?.status == .ok)
            }
        }
    }
}

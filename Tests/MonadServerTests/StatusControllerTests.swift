import Foundation
import Hummingbird
import HummingbirdTesting
@testable import MonadServerCore
import MonadShared
import NIOCore
import PKShared
import PKTestSupport
import PositronicKit
import Testing

struct StatusControllerTests {
    @Test("Test Status Endpoint")
    func statusEndpoint() async throws {
        struct MockDatabase: HealthCheckable {
            func getHealthStatus() async -> HealthStatus {
                .ok
            }

            func getHealthDetails() async -> [String: String]? {
                nil
            }

            func checkHealth() async -> HealthStatus {
                .ok
            }
        }

        let llmService = MockLLMService()
        let router = Router()
        let controller = StatusAPIController<BasicRequestContext>(
            databaseManager: MockDatabase(),
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

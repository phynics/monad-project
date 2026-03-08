import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import NIOCore
import Testing

@Suite struct StatusControllerTests {
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

        try await withDependencies {
            $0.databaseManager = MockDatabase()
            $0.llmService = llmService
        } operation: {
            let router = Router()
            let controller = StatusAPIController<BasicRequestContext>(startTime: Date())
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
}

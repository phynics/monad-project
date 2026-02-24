import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer
import MonadCore
import NIOCore

@Suite struct ConfigurationControllerTests {

    @Test("Test Configuration CRUD")
    func testConfigurationCRUD() async throws {
        let llm = MockLLMService()

        let router = Router()
        let controller = ConfigurationAPIController<BasicRequestContext>(llmService: llm)
        controller.addRoutes(to: router.group("/config"))

        let app = Application(router: router)

        try await app.test(.router) { client in
            // 1. Get
            try await client.execute(uri: "/config", method: .get) { response in
                #expect(response.status == .ok)
                let config = try JSONDecoder().decode(LLMConfiguration.self, from: response.body)
                #expect(config.activeProvider == .openAI)
            }

            // 2. Update
            var newConfig = LLMConfiguration(activeProvider: .ollama)
            newConfig.providers[.ollama]?.apiKey = "test-key" // Ollama doesn't need it but makes it valid for Mock

            let buffer = ByteBuffer(bytes: try JSONEncoder().encode(newConfig))
            try await client.execute(uri: "/config", method: .put, body: buffer) { response in
                #expect(response.status == .ok)
            }

            // 3. Verify
            try await client.execute(uri: "/config", method: .get) { response in
                #expect(response.status == .ok)
                let config = try JSONDecoder().decode(LLMConfiguration.self, from: response.body)
                #expect(config.activeProvider == .ollama)
            }

            // 4. Delete
            try await client.execute(uri: "/config", method: .delete) { response in
                #expect(response.status == .noContent)
            }
        }
    }
}

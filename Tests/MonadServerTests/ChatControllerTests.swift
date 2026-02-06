import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServerCore
import MonadCore
import NIOCore

@Suite struct ChatControllerTests {

    @Test("Test Chat Endpoint")
    func testChatEndpoint() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockClient.nextResponse = "Hello from AI"

        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        let sessionManager = SessionManager(
            persistenceService: persistence,
            embeddingService: embedding,
            llmService: llmService,
            workspaceRoot: workspaceRoot
        )

        // Create Session
        let session = try await sessionManager.createSession()

        // Setup App
        let router = Router()
        let controller = ChatController<BasicRequestContext>(sessionManager: sessionManager, llmService: llmService)
        controller.addRoutes(to: router.group("/sessions"))

        let app = Application(router: router)

        // Test Request
        let chatRequest = ChatRequest(message: "Hello")

        try await app.test(.router) { client in
            let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
            try await client.execute(uri: "/sessions/\(session.id)/chat", method: .post, body: buffer) { response in
                #expect(response.status == .ok)

                let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: response.body)
                #expect(chatResponse.response == "Hello from AI")
            }
        }
    }

    @Test("Test Chat Endpoint Unconfigured")
    func testChatEndpointUnconfigured() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.isConfigured = false

        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        let sessionManager = SessionManager(
            persistenceService: persistence,
            embeddingService: embedding,
            llmService: llmService,
            workspaceRoot: workspaceRoot
        )

        // Create Session
        let session = try await sessionManager.createSession()

        // Setup App
        let router = Router()
        let controller = ChatController<BasicRequestContext>(sessionManager: sessionManager, llmService: llmService)
        controller.addRoutes(to: router.group("/sessions"))

        let app = Application(router: router)

        // Test Request
        let chatRequest = ChatRequest(message: "Hello")

        try await app.test(.router) { client in
            let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
            try await client.execute(uri: "/sessions/\(session.id)/chat", method: .post, body: buffer) { response in
                // We expect an error status code, not a 200 OK with empty body
                #expect(response.status != .ok)
            }
        }
    }
}

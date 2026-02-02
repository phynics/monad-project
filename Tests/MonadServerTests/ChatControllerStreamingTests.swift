import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServerCore
import MonadCore
import NIOCore

@Suite struct ChatControllerStreamingTests {
    
    @Test("Test Chat Streaming Endpoint")
    func testChatStreamingEndpoint() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding)
        let llmService = ServerLLMService()
        
        let mockClient = MockLLMClient()
        mockClient.nextResponses = ["Hello", " ", "World"]
        await llmService.setClients(main: mockClient, utility: mockClient, fast: mockClient)
        
        // Create Session
        let session = try await sessionManager.createSession()
        
        // Setup App
        let router = Router()
        let controller = ChatController<BasicRequestContext>(sessionManager: sessionManager, llmService: llmService)
        controller.addRoutes(to: router.group("/sessions"))
        
        let app = Application(router: router)
        
        // Test Request
        let chatRequest = ChatRequest(message: "Hi")
        
        try await app.test(.router) { client in
            let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
            
            try await client.execute(uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/event-stream")
                
                // Collect body
                let body = try await String(buffer: response.body)
                // SSE format check? 
                // Since MockLLMClient returns ChatStreamResult, we need to see how ChatController handles it.
                // Assuming it sends "data: <content>\n\n"
                #expect(body.contains("Hello"))
                #expect(body.contains("World"))
            }
        }
    }

    @Test("Test Chat Streaming Endpoint Unconfigured")
    func testChatStreamingEndpointUnconfigured() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let sessionManager = SessionManager(persistenceService: persistence, embeddingService: embedding)
        let llmService = ServerLLMService() // Not configured
        
        // Create Session
        let session = try await sessionManager.createSession()
        
        // Setup App
        let router = Router()
        let controller = ChatController<BasicRequestContext>(sessionManager: sessionManager, llmService: llmService)
        controller.addRoutes(to: router.group("/sessions"))
        
        let app = Application(router: router)
        
        // Test Request
        let chatRequest = ChatRequest(message: "Hi")
        
        try await app.test(.router) { client in
            let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
            try await client.execute(uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer) { response in
                #expect(response.status != .ok)
            }
        }
    }
}

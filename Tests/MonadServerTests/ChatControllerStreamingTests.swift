import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServerCore
import MonadCore
import NIOCore
import OpenAI

@Suite struct ChatControllerStreamingTests {
    
    @Test("Test Chat Streaming Endpoint")
    func testChatStreamingEndpoint() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockClient.nextResponses = ["Hello", " ", "World"]
        
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
        let chatRequest = ChatRequest(message: "Hi")
        
        try await app.test(.router) { client in
            let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
            
            try await client.execute(uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer) { response in
                #expect(response.status == .ok)
                #expect(response.headers[.contentType] == "text/event-stream")
                
                // Collect body
                let body = try await String(buffer: await response.body)
                // SSE format check
                #expect(body.contains("data:"))
                #expect(body.contains("[DONE]"))
            }
        }
    }

    @Test("Test Chat Streaming Endpoint Unconfigured")
    func testChatStreamingEndpointUnconfigured() async throws {
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
        let chatRequest = ChatRequest(message: "Hi")
        
        try await app.test(.router) { client in
            let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
            try await client.execute(uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer) { response in
                #expect(response.status != .ok)
            }
        }
    }
}
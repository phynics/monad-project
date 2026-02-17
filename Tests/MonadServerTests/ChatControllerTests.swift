import MonadShared
import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
import Dependencies
@testable import MonadServer
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
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llmService
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
    
            // Create Session
            let session = try await sessionManager.createSession()
    
            try await withDependencies {
                $0.sessionManager = sessionManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.toolRouter = toolRouter
                } operation: {
                    let engine = ChatEngine()
            
                    // Setup App
                    let router = Router()
                    let controller = ChatAPIController<BasicRequestContext>(sessionManager: sessionManager, chatEngine: engine, toolRouter: toolRouter)
                    controller.addRoutes(to: router.group("/sessions"))
            
                    let app = Application(router: router)
            
                    // Test Request
                    let chatRequest = MonadShared.ChatRequest(message: "Hello")
            
                    try await app.test(.router) { client in
                        let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
                        try await client.execute(uri: "/sessions/\(session.id)/chat", method: .post, body: buffer) { response in
                            #expect(response.status == .ok)
            
                            let chatResponse = try JSONDecoder().decode(MonadShared.ChatResponse.self, from: response.body)
                            #expect(chatResponse.response == "Hello from AI")
                        }
                    }
                }
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
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llmService
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
    
            // Create Session
            let session = try await sessionManager.createSession()
    
            try await withDependencies {
                $0.sessionManager = sessionManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.toolRouter = toolRouter
                } operation: {
                    let engine = ChatEngine()
            
                    // Setup App
                    let router = Router()
                    let controller = ChatAPIController<BasicRequestContext>(sessionManager: sessionManager, chatEngine: engine, toolRouter: toolRouter)
                    controller.addRoutes(to: router.group("/sessions"))
            
                    let app = Application(router: router)
            
                    // Test Request
                    let chatRequest = MonadShared.ChatRequest(message: "Hello")
            
                    try await app.test(.router) { client in
                        let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
                        try await client.execute(uri: "/sessions/\(session.id)/chat", method: .post, body: buffer) { response in
                            // We expect an error status code, not a 200 OK with empty body
                            #expect(response.status != .ok)
                        }
                    }
                }
            }
        }
    }
}

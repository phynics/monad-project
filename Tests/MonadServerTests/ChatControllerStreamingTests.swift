import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
import NIOCore
import OpenAI
import Testing
import Dependencies

@testable import MonadServer

@Suite struct ChatControllerStreamingTests {

    @Test("Test Chat Streaming Endpoint")
    func testChatStreamingEndpoint() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockClient.nextResponses = ["Hello", " ", "World"]

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
    
            // We need to inject sessionManager into the context for ToolRouter and ChatOrchestrator
            // Since we created sessionManager explicitly, we should override it in dependencies for subsequent calls
            try await withDependencies {
                $0.sessionManager = sessionManager
            } operation: {
                let toolRouter = ToolRouter()
                // Also override toolRouter for ChatOrchestrator
                try await withDependencies {
                    $0.toolRouter = toolRouter
                } operation: {
                    let orchestrator = ChatOrchestrator()
            
                    // Setup App
                    let router = Router()
                    let controller = ChatAPIController<BasicRequestContext>(
                        sessionManager: sessionManager, chatOrchestrator: orchestrator)
                    controller.addRoutes(to: router.group("/sessions"))
            
                    let app = Application(router: router)
            
                    // Test Request
                    let chatRequest = ChatRequest(message: "Hi")
            
                    try await app.test(.router) { client in
                        let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
            
                        try await client.execute(
                            uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer
                        ) { response in
                            #expect(response.status == .ok)
                            #expect(response.headers[.contentType] == "text/event-stream")
            
                            // Collect body
                            let body = try await String(buffer: await response.body)
                            // SSE format check
                            #expect(body.contains("data:"))
                            #expect(body.contains("\"isDone\":true"))
                        }
                    }
                }
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
                    let orchestrator = ChatOrchestrator()
            
                    // Setup App
                    let router = Router()
                    let controller = ChatAPIController<BasicRequestContext>(
                        sessionManager: sessionManager, chatOrchestrator: orchestrator)
                    controller.addRoutes(to: router.group("/sessions"))
            
                    let app = Application(router: router)
            
                    // Test Request
                    let chatRequest = ChatRequest(message: "Hi")
            
                    try await app.test(.router) { client in
                        let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))
                        try await client.execute(
                            uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer
                        ) { response in
                            #expect(response.status != .ok)
                        }
                    }
                }
            }
        }
    }
}

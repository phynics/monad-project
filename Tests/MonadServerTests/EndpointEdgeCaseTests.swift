import MonadShared
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import MonadCore
import NIOCore
import Testing
import Dependencies

@testable import MonadServer

@Suite struct EndpointEdgeCaseTests {

    @Test("Chat with non-existent session (404)")
    func testChatNoSession() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
            
            // We need to inject sessionManager into the context for ToolRouter and ChatOrchestrator
            try await withDependencies {
                $0.sessionManager = sessionManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.toolRouter = toolRouter
                } operation: {
                    let orchestrator = ChatOrchestrator()
            
                    let router = Router()
                    router.add(middleware: ErrorMiddleware())
                    let protected = router.group("/api").add(middleware: AuthMiddleware())
                    ChatAPIController<BasicRequestContext>(
                        sessionManager: sessionManager, chatOrchestrator: orchestrator
                    ).addRoutes(to: protected.group("/sessions"))
            
                    let app = Application(router: router)
            
                    let req = MonadShared.ChatRequest(message: "Hi")
                    let buffer = ByteBuffer(bytes: try JSONEncoder().encode(req))
            
                    try await app.test(.router) { client in
                        var headers = HTTPFields()
                        headers[.authorization] = "Bearer monad-secret"
                        try await client.execute(
                            uri: "/api/sessions/\(UUID())/chat", method: .post,
                            headers: headers, body: buffer
                        ) { response in
                            #expect(response.status == .notFound)
                        }
                    }
                }
            }
        }
    }

    @Test("Chat with invalid UUID (400)")
    func testChatInvalidUUID() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
    
            try await withDependencies {
                $0.sessionManager = sessionManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.toolRouter = toolRouter
                } operation: {
                    let orchestrator = ChatOrchestrator()
            
                    let router = Router()
                    router.add(middleware: ErrorMiddleware())
                    let protected = router.group("/api").add(middleware: AuthMiddleware())
                    ChatAPIController<BasicRequestContext>(
                        sessionManager: sessionManager, chatOrchestrator: orchestrator
                    ).addRoutes(to: protected.group("/sessions"))
            
                    let app = Application(router: router)
            
                    let req = MonadShared.ChatRequest(message: "Hi")
                    let buffer = ByteBuffer(bytes: try JSONEncoder().encode(req))
            
                    try await app.test(.router) { client in
                        var headers = HTTPFields()
                        headers[.authorization] = "Bearer monad-secret"
                        try await client.execute(
                            uri: "/api/sessions/invalid-uuid/chat", method: .post,
                            headers: headers, body: buffer
                        ) { response in
                            #expect(response.status == .badRequest)
                        }
                    }
                }
            }
        }
    }

    @Test("Auth Failure: Missing Header (Permissive -> 200 OK)")
    func testAuthMissingHeader() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
    
            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let protected = router.group("/api").add(middleware: AuthMiddleware())
            MemoryAPIController<BasicRequestContext>(sessionManager: sessionManager).addRoutes(
                to: protected.group("/memories"))
    
            let app = Application(router: router)
    
            try await app.test(.router) { client in
                try await client.execute(uri: "/api/memories", method: .get) { response in
                    // With permissive auth, request proceeds to controller
                    #expect(response.status == .ok)
                }
            }
        }
    }

    @Test("Auth Failure: Invalid Token (Permissive -> 200 OK)")
    func testAuthInvalidToken() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
    
            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let protected = router.group("/api").add(middleware: AuthMiddleware())
            MemoryAPIController<BasicRequestContext>(sessionManager: sessionManager).addRoutes(
                to: protected.group("/memories"))
    
            let app = Application(router: router)
    
            try await app.test(.router) { client in
                var headers = HTTPFields()
                headers[.authorization] = "Bearer wrong"
                try await client.execute(uri: "/api/memories", method: .get, headers: headers) {
                    response in
                    // With permissive auth, request proceeds to controller
                    #expect(response.status == .ok)
                }
            }
        }
    }

    @Test("Delete non-existent memory (Should be 204)")
    func testDeleteNoMemory() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)
        
        try await withDependencies {
            $0.persistenceService = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentRegistry = AgentRegistry()
        } operation: {
            let sessionManager = SessionManager(
                workspaceRoot: workspaceRoot
            )
    
            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let protected = router.group("/api").add(middleware: AuthMiddleware())
            MemoryAPIController<BasicRequestContext>(sessionManager: sessionManager).addRoutes(
                to: protected.group("/memories"))
    
            let app = Application(router: router)
    
            try await app.test(.router) { client in
                var headers = HTTPFields()
                headers[.authorization] = "Bearer monad-secret"
                try await client.execute(
                    uri: "/api/memories/\(UUID())", method: .delete, headers: headers
                ) { response in
                    #expect(response.status == .noContent)
                }
            }
        }
    }
}

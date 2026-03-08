import MonadShared
import MonadCore
import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import NIOCore
import Testing
import Dependencies

import MonadTestSupport
@testable import MonadServer

@Suite struct EndpointEdgeCaseTests {

    @Test("Chat with non-existent session (404)")
    func testChatNoSession() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.backgroundJobStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            // We need to inject timelineManager into the context for ToolRouter and ChatEngine
            try await withDependencies {
                $0.timelineManager = timelineManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.toolRouter = toolRouter
                } operation: {
                    let engine = ChatEngine()

                    let router = Router()
                    router.add(middleware: ErrorMiddleware())
                    let protected = router.group("/api").add(middleware: AuthMiddleware())
                    ChatAPIController<BasicRequestContext>().addRoutes(to: protected.group("/sessions"))

                    let app = Application(router: router)

                    let req = ChatRequest(message: "Hi")
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
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.backgroundJobStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            try await withDependencies {
                $0.timelineManager = timelineManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.toolRouter = toolRouter
                } operation: {
                    let engine = ChatEngine()

                    let router = Router()
                    router.add(middleware: ErrorMiddleware())
                    let protected = router.group("/api").add(middleware: AuthMiddleware())
                    ChatAPIController<BasicRequestContext>().addRoutes(to: protected.group("/sessions"))

                    let app = Application(router: router)

                    let req = ChatRequest(message: "Hi")
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

    @Test("Auth Failure: Missing Header (Strict -> 401 Unauthorized)")
    func testAuthMissingHeader() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.backgroundJobStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let protected = router.group("/api").add(middleware: AuthMiddleware())
            MemoryAPIController<BasicRequestContext>().addRoutes(
                to: protected.group("/memories"))

            let app = Application(router: router)

            try await app.test(.router) { client in
                try await client.execute(uri: "/api/memories", method: .get) { response in
                    // With strict auth, request is blocked
                    #expect(response.status == .unauthorized)
                }
            }
        }
    }

    @Test("Auth Failure: Invalid Token (Strict -> 401 Unauthorized)")
    func testAuthInvalidToken() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llm = MockLLMService()
        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.backgroundJobStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let protected = router.group("/api").add(middleware: AuthMiddleware())
            MemoryAPIController<BasicRequestContext>().addRoutes(
                to: protected.group("/memories"))

            let app = Application(router: router)

            try await app.test(.router) { client in
                var headers = HTTPFields()
                headers[.authorization] = "Bearer wrong"
                try await client.execute(uri: "/api/memories", method: .get, headers: headers) {
                    response in
                    // With strict auth, request is blocked
                    #expect(response.status == .unauthorized)
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
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.backgroundJobStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llm
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            let router = Router()
            router.add(middleware: ErrorMiddleware())
            let protected = router.group("/api").add(middleware: AuthMiddleware())
            MemoryAPIController<BasicRequestContext>().addRoutes(
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

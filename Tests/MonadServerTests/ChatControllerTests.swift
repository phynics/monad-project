import MonadShared
import MonadCore
import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
import Dependencies
import MonadTestSupport
@testable import MonadServer
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
            $0.llmService = llmService
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            // Create Session
            let session = try await timelineManager.createTimeline()
            
            // Attach an agent
            let agentId = UUID()
            let agent = AgentInstance(id: agentId, name: "Test Agent", description: "Test", primaryWorkspaceId: UUID(), privateTimelineId: UUID())
            try await persistence.saveAgentInstance(agent)
            var updatedSession = session
            updatedSession.attachedAgentInstanceId = agentId
            try await persistence.saveTimeline(updatedSession)
            
            // Clear cache
            await timelineManager.deleteTimeline(id: session.id)

            try await withDependencies {
                $0.timelineManager = timelineManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.chatEngine = ChatEngine()
                    $0.toolRouter = toolRouter
                } operation: {

                    // Setup App
                    let router = Router()
                    let controller = ChatAPIController<BasicRequestContext>()
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
            }
        }
    }

    @Test("Test Chat Endpoint Unconfigured")
    func testChatEndpointUnconfigured() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockIsConfigured = false

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
            $0.llmService = llmService
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            // Create Session
            let session = try await timelineManager.createTimeline()
            
            // Attach an agent
            let agentId = UUID()
            let agent = AgentInstance(id: agentId, name: "Test Agent", description: "Test", primaryWorkspaceId: UUID(), privateTimelineId: UUID())
            try await persistence.saveAgentInstance(agent)
            var updatedSession = session
            updatedSession.attachedAgentInstanceId = agentId
            try await persistence.saveTimeline(updatedSession)
            
            // Clear cache
            await timelineManager.deleteTimeline(id: session.id)

            try await withDependencies {
                $0.timelineManager = timelineManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.chatEngine = ChatEngine()
                    $0.toolRouter = toolRouter
                } operation: {

                    // Setup App
                    let router = Router()
                    let controller = ChatAPIController<BasicRequestContext>()
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
        }
    }
}

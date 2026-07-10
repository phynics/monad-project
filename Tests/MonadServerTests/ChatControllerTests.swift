import Foundation
import Hummingbird
import HummingbirdTesting
@testable import MonadServerCore
import MonadShared
import NIOCore
import PKShared
import PKTestSupport
import PositronicKit
import Testing

struct ChatControllerTests {
    @Test("Test Chat Endpoint")
    func chatEndpoint() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockClient.nextResponse = "Hello from AI"

        let workspace = TestWorkspace()

        let runtime = TestRuntime(workspaceRoot: workspace.root, persistence: persistence, llm: llmService, embedding: embedding)
        let timelineManager = runtime.timelineManager
        let toolRouter = runtime.toolRouter
        let agentInstanceStore = persistence

        let session = try await timelineManager.createTimeline()

        let agentId = UUID()
        let agent = AgentInstance(id: agentId, name: "Test Agent", description: "Test", primaryWorkspaceId: UUID(), privateTimelineId: UUID())
        try await persistence.saveAgentInstance(agent)
        var updatedSession = session
        updatedSession.attachedAgentInstanceId = agentId
        try await persistence.saveTimeline(updatedSession)

        await timelineManager.deleteTimeline(id: session.id)

        let router = Router()
        let controller = ChatAPIController<BasicRequestContext>(
            chat: runtime.buildCore(),
            timelineManager: timelineManager,
            agentInstanceStore: agentInstanceStore,
            toolRouter: toolRouter
        )
        controller.addRoutes(to: router.group("/sessions"))
        let app = Application(router: router)

        let chatRequest = ChatRequest(message: "Hello")

        try await app.test(.router) { client in
            let buffer = try ByteBuffer(bytes: JSONEncoder().encode(chatRequest))
            try await client.execute(uri: "/sessions/\(session.id)/chat", method: .post, body: buffer) { response in
                #expect(response.status == .ok)

                let chatResponse = try JSONDecoder().decode(ChatResponse.self, from: response.body)
                #expect(chatResponse.response == "Hello from AI")
            }
        }
    }

    @Test("Test Chat Endpoint Unconfigured")
    func chatEndpointUnconfigured() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockIsConfigured = false

        let workspace = TestWorkspace()

        let runtime = TestRuntime(workspaceRoot: workspace.root, persistence: persistence, llm: llmService, embedding: embedding)
        let timelineManager = runtime.timelineManager
        let toolRouter = runtime.toolRouter
        let agentInstanceStore = persistence

        let session = try await timelineManager.createTimeline()

        let agentId = UUID()
        let agent = AgentInstance(id: agentId, name: "Test Agent", description: "Test", primaryWorkspaceId: UUID(), privateTimelineId: UUID())
        try await persistence.saveAgentInstance(agent)
        var updatedSession = session
        updatedSession.attachedAgentInstanceId = agentId
        try await persistence.saveTimeline(updatedSession)

        await timelineManager.deleteTimeline(id: session.id)

        let router = Router()
        let controller = ChatAPIController<BasicRequestContext>(
            chat: runtime.buildCore(),
            timelineManager: timelineManager,
            agentInstanceStore: agentInstanceStore,
            toolRouter: toolRouter
        )
        controller.addRoutes(to: router.group("/sessions"))
        let app = Application(router: router)

        let chatRequest = ChatRequest(message: "Hello")

        try await app.test(.router) { client in
            let buffer = try ByteBuffer(bytes: JSONEncoder().encode(chatRequest))
            try await client.execute(uri: "/sessions/\(session.id)/chat", method: .post, body: buffer) { response in
                #expect(response.status != .ok)
            }
        }
    }
}

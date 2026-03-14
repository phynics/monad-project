import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import NIOCore
import OpenAI
import Testing

@Suite struct ChatControllerStreamingTests {
    @Test("Test Chat Streaming Endpoint")
    func chatStreamingEndpoint() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockClient.nextResponses = ["Hello", " ", "World"]

        let workspace = TestWorkspace()

        try await TestDependencies()
            .withMocks(persistence: persistence, llm: llmService, embedding: embedding)
            .withOrchestration(workspaceRoot: workspace.root)
            .run {
                @Dependency(\.timelineManager) var timelineManager

                // Create Session
                let session = try await timelineManager.createTimeline()

                // Attach an agent
                let agentId = UUID()
                let agent = AgentInstance(
                    id: agentId, name: "Test Agent", description: "Test",
                    primaryWorkspaceId: UUID(), privateTimelineId: UUID()
                )
                try await persistence.saveAgentInstance(agent)
                var updatedSession = session
                updatedSession.attachedAgentInstanceId = agentId
                try await persistence.saveTimeline(updatedSession)

                // Clear cache to force re-hydration with agent
                await timelineManager.deleteTimeline(id: session.id)

                // Setup App
                let router = Router()
                let controller = ChatAPIController<BasicRequestContext>()
                controller.addRoutes(to: router.group("/sessions"))

                let app = Application(router: router)

                // Test Request
                let chatRequest = ChatRequest(message: "Hi")

                try await app.test(.router) { client in
                    let buffer = try ByteBuffer(bytes: JSONEncoder().encode(chatRequest))

                    try await client.execute(
                        uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer
                    ) { response in
                        #expect(response.status == .ok)
                        #expect(response.headers[.contentType] == "text/event-stream")

                        // Collect body
                        let body = String(buffer: response.body)
                        // SSE format check
                        #expect(body.contains("data:"))
                        #expect(body.contains("\"streamCompleted\""))
                    }
                }
            }
    }

    @Test("Test Chat Cancellation")
    func chatCancellation() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockClient.nextChunks = [["Thinking...", "Wait...", "Finished!"]]
        llmService.mockClient.nextStreamWait = 1.0 // Slow down stream more

        let workspace = TestWorkspace()

        try await TestDependencies()
            .withMocks(persistence: persistence, llm: llmService, embedding: embedding)
            .withOrchestration(workspaceRoot: workspace.root)
            .with { $0.continuousClock = ContinuousClock() }
            .run {
                @Dependency(\.timelineManager) var timelineManager

                let session = try await timelineManager.createTimeline()

                // Attach an agent
                let agentId = UUID()
                let agent = AgentInstance(
                    id: agentId, name: "Test Agent", description: "Test",
                    primaryWorkspaceId: UUID(), privateTimelineId: UUID()
                )
                try await persistence.saveAgentInstance(agent)
                var updatedSession = session
                updatedSession.attachedAgentInstanceId = agentId
                try await persistence.saveTimeline(updatedSession)

                // Clear cache to force re-hydration with agent
                await timelineManager.deleteTimeline(id: session.id)

                let router = Router()
                let controller = ChatAPIController<BasicRequestContext>()
                controller.addRoutes(to: router.group("/sessions"))
                let app = Application(router: router)
                let chatRequest = ChatRequest(message: "Wait for it")

                try await app.test(.router) { client in
                    let buffer = try ByteBuffer(bytes: JSONEncoder().encode(chatRequest))

                    // Start stream in background
                    let streamTask = Task {
                        try await client.execute(
                            uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer
                        ) { response in
                            #expect(response.status == .ok)
                            let body = String(buffer: response.body)
                            #expect(body.contains("\"generationCancelled\""))
                        }
                    }

                    // Wait for stream to start (enough time for timelineManager to register task)
                    try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

                    // Cancel
                    try await client.execute(
                        uri: "/sessions/\(session.id)/chat/cancel", method: .post
                    ) { response in
                        #expect(response.status == .ok)
                    }

                    try await streamTask.value
                }
            }
    }

    @Test("Test Chat Streaming Endpoint Unconfigured")
    func chatStreamingEndpointUnconfigured() async throws {
        // Setup Deps
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockIsConfigured = false

        let workspace = TestWorkspace()

        try await TestDependencies()
            .withMocks(persistence: persistence, llm: llmService, embedding: embedding)
            .withOrchestration(workspaceRoot: workspace.root)
            .run {
                @Dependency(\.timelineManager) var timelineManager

                // Create Session
                let session = try await timelineManager.createTimeline()

                // Setup App
                let router = Router()
                let controller = ChatAPIController<BasicRequestContext>()
                controller.addRoutes(to: router.group("/sessions"))

                let app = Application(router: router)

                // Test Request
                let chatRequest = ChatRequest(message: "Hi")

                try await app.test(.router) { client in
                    let buffer = try ByteBuffer(bytes: JSONEncoder().encode(chatRequest))
                    try await client.execute(
                        uri: "/sessions/\(session.id)/chat/stream", method: .post, body: buffer
                    ) { response in
                        #expect(response.status != .ok)
                    }
                }
            }
    }
}

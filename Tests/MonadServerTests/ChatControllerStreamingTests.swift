import MonadShared
import MonadCore
import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import OpenAI
import Testing
import Dependencies

import MonadTestSupport
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
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llmService
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
            
            // Clear cache to force re-hydration with agent
            await timelineManager.deleteTimeline(id: session.id)

            // We need to inject timelineManager into the context for ToolRouter and ChatEngine
            // Since we created timelineManager explicitly, we should override it in dependencies for subsequent calls
            try await withDependencies {
                $0.timelineManager = timelineManager
            } operation: {
                let toolRouter = ToolRouter()
                // Also override toolRouter for ChatEngine
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
                    let chatRequest = ChatRequest(message: "Hi")

                    try await app.test(.router) { client in
                        let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))

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
        }
    }

    @Test("Test Chat Cancellation")
    func testChatCancellation() async throws {
        let persistence = MockPersistenceService()
        let embedding = MockEmbeddingService()
        let llmService = MockLLMService()
        llmService.mockClient.nextChunks = [["Thinking...", "Wait...", "Finished!"]]
        llmService.mockClient.nextStreamWait = 1.0 // Slow down stream more

        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llmService
        } operation: {
            let timelineManager = TimelineManager(workspaceRoot: workspaceRoot)
            let session = try await timelineManager.createTimeline()
            
            // Attach an agent
            let agentId = UUID()
            let agent = AgentInstance(id: agentId, name: "Test Agent", description: "Test", primaryWorkspaceId: UUID(), privateTimelineId: UUID())
            try await persistence.saveAgentInstance(agent)
            var updatedSession = session
            updatedSession.attachedAgentInstanceId = agentId
            try await persistence.saveTimeline(updatedSession)
            
            // Clear cache to force re-hydration with agent
            await timelineManager.deleteTimeline(id: session.id)

            try await withDependencies {
                $0.timelineManager = timelineManager
            } operation: {
                let toolRouter = ToolRouter()
                try await withDependencies {
                    $0.chatEngine = ChatEngine()
                    $0.toolRouter = toolRouter
                } operation: {
                    let router = Router()
                    let controller = ChatAPIController<BasicRequestContext>()
                    controller.addRoutes(to: router.group("/sessions"))
                    let app = Application(router: router)
                    let chatRequest = ChatRequest(message: "Wait for it")

                    try await app.test(.router) { client in
                        let buffer = ByteBuffer(bytes: try JSONEncoder().encode(chatRequest))

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
                        try await client.execute(uri: "/sessions/\(session.id)/chat/cancel", method: .post) { response in
                            #expect(response.status == .ok)
                        }

                        try await streamTask.value
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
        llmService.mockIsConfigured = false

        let workspaceRoot = getTestWorkspaceRoot().appendingPathComponent(UUID().uuidString)

        try await withDependencies {
            $0.timelinePersistence = persistence
            $0.workspacePersistence = persistence
            $0.memoryStore = persistence
            $0.messageStore = persistence
            $0.agentTemplateStore = persistence
            $0.clientStore = persistence
            $0.toolPersistence = persistence
            $0.agentInstanceStore = persistence
            $0.embeddingService = embedding
            $0.llmService = llmService
        } operation: {
            let timelineManager = TimelineManager(
                workspaceRoot: workspaceRoot
            )

            // Create Session
            let session = try await timelineManager.createTimeline()

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

import Foundation
import MonadCore
import Testing

@testable import MonadServer

@Suite struct ServerLLMServiceTests {

    @Test("Test ServerLLMService Initialization and Config Load")
    func testInitialization() async throws {
        let defaults = UserDefaults(suiteName: "TestServerLLMService")!
        defaults.removePersistentDomain(forName: "TestServerLLMService")

        let storage = ConfigurationStorage(userDefaults: defaults)
        let service = ServerLLMService(storage: storage)

        await service.loadConfiguration()

        let client = await service.getClient()
        #expect(client == nil, "Client should be nil initially (no API Key)")

        // Test updating configuration
        var config = await service.configuration
        config.activeProvider = .ollama
        config.providers[.ollama]?.modelName = "test-model"
        // Ollama doesn't need API Key, just endpoint
        config.providers[.ollama]?.endpoint = "http://localhost:11434/api"

        try await service.updateConfiguration(config)

        let newConfig = await service.configuration
        #expect(newConfig.activeProvider == .ollama)

        let newClient = await service.getClient()
        #expect(newClient != nil, "Client should be initialized after valid config")
    }

    @Test("Test generateTags")
    func testGenerateTags() async throws {
        let storage = ConfigurationStorage(userDefaults: UserDefaults(suiteName: "TestTags")!)
        let service = ServerLLMService(storage: storage)

        // Setup mock config
        var config = LLMConfiguration.openAI
        config.providers[.openAI]?.apiKey = "test-key"
        try await service.updateConfiguration(config)

        // Access internal or force mock injection if possible,
        // but since we only have public API, we might need a way to inject mock client.
        // ServerLLMService uses `setClients` internally.
        // We can use a trick: `ServerTestMocks.swift` defines `MockLLMClient`.
        // But `ServerLLMService` creates concrete clients based on config.
        // WAITING: We need to be able to inject a mock client into ServerLLMService for unit testing without real network calls.
        // Inspecting ServerLLMService, `setClients` is internal. We can use `@testable import`.

        let mockClient = MockLLMClient()
        mockClient.nextResponse = """
            {
                "tags": ["swift", "testing", "llm"]
            }
            """

        // Inject mock
        await service.setClients(main: mockClient, utility: mockClient, fast: mockClient)

        let tags = try await service.generateTags(for: "This is a post about Swift testing.")
        #expect(tags == ["swift", "testing", "llm"])
        #expect(mockClient.lastMessages.count > 0)
    }

    @Test("Test generateTitle")
    func testGenerateTitle() async throws {
        let storage = ConfigurationStorage(userDefaults: UserDefaults(suiteName: "TestTitle")!)
        let service = ServerLLMService(storage: storage)

        let mockClient = MockLLMClient()
        mockClient.nextResponse = "Test Conversation"

        await service.setClients(main: mockClient, utility: mockClient, fast: mockClient)

        let messages: [Message] = [
            Message(content: "Hello", role: .user),
            Message(content: "Hi there", role: .assistant)
        ]

        let title = try await service.generateTitle(for: messages)
        #expect(title == "Test Conversation")
    }

    @Test("Test evaluateRecallPerformance")
    func testEvaluateRecallPerformance() async throws {
        let storage = ConfigurationStorage(userDefaults: UserDefaults(suiteName: "TestRecall")!)
        let service = ServerLLMService(storage: storage)

        let mockClient = MockLLMClient()
        mockClient.nextResponse = """
            {
                "uuid-1": 1.0,
                "uuid-2": -0.5
            }
            """

        await service.setClients(main: mockClient, utility: mockClient, fast: mockClient)

        let memory1 = Memory(
            id: UUID(), title: "Mem1", content: "Content1", tags: [], embedding: [])

        // We'll just verify parsing, the map keys won't match UUIDs generated above unless we mock the response to match.
        // Actually, we can just check if *result* matches our mock.

        let scores = try await service.evaluateRecallPerformance(
            transcript: "chat", recalledMemories: [memory1])
        // The mock response keys "uuid-1" won't match memory1.id, but the function returns the map as-is.
        #expect(scores["uuid-1"] == 1.0)
        #expect(scores["uuid-2"] == -0.5)
    }

    @Test("Test chatStreamWithContext")
    func testChatStreamWithContext() async throws {
        let storage = ConfigurationStorage(userDefaults: UserDefaults(suiteName: "TestStream")!)
        let service = ServerLLMService(storage: storage)

        let mockClient = MockLLMClient()
        mockClient.nextResponse = "Hello"

        await service.setClients(main: mockClient, utility: mockClient, fast: mockClient)

        let (stream, prompt, _) = await service.chatStreamWithContext(
            userQuery: "Hi",
            contextNotes: [],
            documents: [],
            memories: [],
            chatHistory: [],
            tools: [],
            systemInstructions: nil,
            responseFormat: nil,
            useFastModel: false
        )

        #expect(!prompt.isEmpty)

        var received = ""
        for try await result in stream {
            for choice in result.choices {
                if let content = choice.delta.content {
                    received += content
                }
            }
        }
        #expect(received == "Hello")
    }

    @Test("Test Provider Configuration (OpenRouter)")
    func testProviderConfiguration() async throws {
        let storage = ConfigurationStorage(userDefaults: UserDefaults(suiteName: "TestConfig")!)
        let service = ServerLLMService(storage: storage)

        var config = LLMConfiguration.openAI
        config.activeProvider = .openRouter
        config.providers[.openRouter]?.apiKey = "sk-or-test"
        config.providers[.openRouter]?.modelName = "anthropic/claude-3"

        try await service.updateConfiguration(config)

        let client = await service.getClient()
        #expect(client != nil)

        // Verify internal state if possible, or just trust getClient() != nil
        // Ideally we check if it is indeed an OpenRouterClient, but type eraser hides it.
    }
}

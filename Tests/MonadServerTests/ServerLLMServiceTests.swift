import MonadShared
import MonadCore
import Foundation
@testable import MonadServer
import MonadTestSupport
import OpenAI
import Testing

@Suite struct LLMServiceTests {
    @Test("Test LLMService Initialization and Config Load")
    func initialization() async throws {
        let defaults = try #require(UserDefaults(suiteName: "TestLLMService"))
        defaults.removePersistentDomain(forName: "TestLLMService")

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = ConfigurationStorage(configURL: tempURL, userDefaults: defaults)
        let service = LLMService(storage: storage)

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

        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Test generateTags")
    func testGenerateTags() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try ConfigurationStorage(
            configURL: tempURL,
            userDefaults: #require(UserDefaults(suiteName: "TestTags"))
        )
        let service = LLMService(storage: storage)

        // Setup mock config
        var config = LLMConfiguration.openAI
        config.providers[.openAI]?.apiKey = "test-key"
        try await service.updateConfiguration(config)

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

        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Test generateTitle")
    func testGenerateTitle() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try ConfigurationStorage(
            configURL: tempURL,
            userDefaults: #require(UserDefaults(suiteName: "TestTitle"))
        )
        let service = LLMService(storage: storage)

        let mockClient = MockLLMClient()
        mockClient.nextResponse = "Test Conversation"

        await service.setClients(main: mockClient, utility: mockClient, fast: mockClient)

        let messages: [Message] = [
            Message(content: "Hello", role: .user),
            Message(content: "Hi there", role: .assistant),
        ]

        let title = try await service.generateTitle(for: messages)
        #expect(title == "Test Conversation")

        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Test evaluateRecallPerformance")
    func testEvaluateRecallPerformance() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try ConfigurationStorage(
            configURL: tempURL,
            userDefaults: #require(UserDefaults(suiteName: "TestRecall"))
        )
        let service = LLMService(storage: storage)

        let mockClient = MockLLMClient()
        mockClient.nextResponse = """
        {
            "uuid-1": 1.0,
            "uuid-2": -0.5
        }
        """

        await service.setClients(main: mockClient, utility: mockClient, fast: mockClient)

        let memory1 = Memory(
            id: UUID(), title: "Mem1", content: "Content1", tags: [], embedding: []
        )

        let scores = try await service.evaluateRecallPerformance(
            transcript: "chat", recalledMemories: [memory1]
        )
        #expect(scores["uuid-1"] == 1.0)
        #expect(scores["uuid-2"] == -0.5)

        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Test chatStreamWithContext")
    func testChatStreamWithContext() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try ConfigurationStorage(
            configURL: tempURL,
            userDefaults: #require(UserDefaults(suiteName: "TestStream"))
        )
        let service = LLMService(storage: storage)

        let mockClient = MockLLMClient()
        mockClient.nextResponse = "Hello"

        await service.setClients(main: mockClient, utility: mockClient, fast: mockClient)

        let (stream, prompt, _) = await service.chatStreamWithContext(
            userQuery: "Hi",
            contextNotes: [],
            memories: [],
            chatHistory: [],
            tools: [],
            workspaces: [],
            primaryWorkspace: nil,
            clientName: nil,
            connectedClients: [],
            systemInstructions: nil as String?,
            responseFormat: nil as ChatQuery.ResponseFormat?,
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

        try? FileManager.default.removeItem(at: tempURL)
    }

    @Test("Test Provider Configuration (OpenRouter)")
    func providerConfiguration() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = try ConfigurationStorage(
            configURL: tempURL,
            userDefaults: #require(UserDefaults(suiteName: "TestConfig"))
        )
        let service = LLMService(storage: storage)

        var config = LLMConfiguration.openAI
        config.activeProvider = .openRouter
        config.providers[.openRouter]?.apiKey = "sk-or-test"
        config.providers[.openRouter]?.modelName = "anthropic/claude-3"

        try await service.updateConfiguration(config)

        let client = await service.getClient()
        #expect(client != nil)

        try? FileManager.default.removeItem(at: tempURL)
    }
}

import OpenAI
import MonadCore
import Testing

@testable import MonadCore

@Suite @MainActor
struct LLMServiceTests {
    private let llmService: LLMService

    init() async {
        llmService = await LLMService()
    }

    @Test("Test updating LLM configuration")
    func configurationUpdate() async throws {
        let config = LLMConfiguration(
            endpoint: "https://test.api.com",
            modelName: "test-model",
            apiKey: "test-key"
        )

        try await llmService.updateConfiguration(config)

        #expect(llmService.isConfigured)
        #expect(llmService.configuration.modelName == "test-model")
    }

    @Test("Test prompt building logic")
    func promptBuilding() async throws {
        let promptBuilder = PromptBuilder()
        let notes = [
            Note(name: "Test Note", content: "Note Content")
        ]
        let history = [
            Message(content: "Previous user message", role: .user)
        ]

        let (messages, rawPrompt, _) = await promptBuilder.buildPrompt(
            systemInstructions: "System rules",
            contextNotes: notes,
            tools: [],
            chatHistory: history,
            userQuery: "Current question"
        )

        #expect(rawPrompt.contains("System rules"))
        #expect(rawPrompt.contains("Note Content"))
        #expect(rawPrompt.contains("Previous user message"))
        #expect(rawPrompt.contains("Current question"))

        // Final message should be the user query
        #expect(messages.last?.role == .user)
    }

    @Test("Test PromptBuilder truncation with large history")
    func promptTruncation() async throws {
        let promptBuilder = PromptBuilder(maxContextTokens: 100)

        // Create a large history that should be truncated
        let largeHistory = (1...10).map { i in
            Message(
                content:
                    "Message \(i) with some significant length to trigger early truncation logic in the builder.",
                role: .user)
        }

        let (messages, _, _) = await promptBuilder.buildPrompt(
            contextNotes: [],
            chatHistory: largeHistory,
            userQuery: "Trigger truncation"
        )

        // Should have fewer messages than total history + user query
        #expect(messages.count < largeHistory.count + 1)
        #expect(messages.last?.role == .user)  // User query always included
    }

    @Test("Test LLMService error when not configured")
    func unconfiguredServiceError() async throws {
        let service = await LLMService()
        // No configuration provided

        await #expect(throws: LLMServiceError.notConfigured) {
            _ = try await service.sendMessage("Hello")
        }
    }

    @Test("Test generateTitle method")
    func titleGeneration() async throws {
        let mockClient = MockLLMClient()
        mockClient.nextResponse = "SwiftUI Basics"
        
        let service = await LLMService(utilityClient: mockClient)
        
        let messages = [
            Message(content: "How do I use SwiftUI?", role: .user),
            Message(content: "You use it by declaring views.", role: .assistant)
        ]
        
        let title = try await service.generateTitle(for: messages)
        #expect(title == "SwiftUI Basics")
        
        // Verify transcript was sent in the prompt
        if let lastMessage = mockClient.lastMessages.last {
            if case .user(let m) = lastMessage, case .string(let content) = m.content {
                #expect(content.contains("How do I use SwiftUI?"))
                #expect(content.contains("You use it by declaring views."))
            }
        }
    }
}

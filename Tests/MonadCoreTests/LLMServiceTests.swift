import OpenAI
import MonadCore
import Testing

@testable import MonadCore

@Suite @MainActor
struct LLMServiceTests {
    private let llmService: LLMService

    init() {
        llmService = LLMService()
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

    @Test("Test prompt building logic and structure")
    func promptBuilding() async throws {
        let promptBuilder = PromptBuilder()
        let notes = [
            Note(name: "Test Note", content: "Note Content")
        ]
        let history = [
            Message(content: "Previous user message", role: .user),
            Message(content: "Previous assistant message", role: .assistant)
        ]

        let (messages, rawPrompt, _) = await promptBuilder.buildPrompt(
            systemInstructions: "System rules",
            contextNotes: notes,
            tools: [],
            chatHistory: history,
            userQuery: "Current question"
        )

        // Validate basic content presence
        #expect(rawPrompt.contains("System rules"))
        #expect(rawPrompt.contains("Note Content"))
        #expect(rawPrompt.contains("Previous user message"))
        #expect(rawPrompt.contains("Current question"))

        // Validate message ordering and roles
        #expect(!messages.isEmpty)

        // 1. System message should be first
        if let first = messages.first, case .system = first {
            // Success
        } else {
            #expect(Bool(false), "First message should be system message")
        }

        // 2. Chat history should follow
        // We look for the messages from history. Note that system prompts might be consolidated.
        // The messages array passed to LLM usually is [System, ...History, UserQuery]

        let historyStart = messages.dropFirst() // Drop system

        // Find "Previous user message"
        var foundHistoryUser = false
        for msg in historyStart {
            if case .user(let m) = msg, case .string(let content) = m.content {
                if content == "Previous user message" {
                    foundHistoryUser = true
                    break
                }
            }
        }
        #expect(foundHistoryUser)

        // Find "Previous assistant message"
        var foundHistoryAssistant = false
        for msg in historyStart {
             if case .assistant(let m) = msg, let contentWrap = m.content, case .textContent(let content) = contentWrap {
                if content == "Previous assistant message" {
                    foundHistoryAssistant = true
                    break
                }
            }
        }
        #expect(foundHistoryAssistant)

        // 3. Final message should be the user query
        guard let lastMessage = messages.last else {
            #expect(Bool(false), "Messages should not be empty")
            return
        }

        if case .user(let m) = lastMessage, case .string(let content) = m.content {
            #expect(content == "Current question")
        } else {
            #expect(Bool(false), "Last message should be user query")
        }
    }

    @Test("Test prompt building with empty context")
    func promptBuildingEmptyContext() async throws {
        let promptBuilder = PromptBuilder()
        let (messages, _, _) = await promptBuilder.buildPrompt(
            systemInstructions: "System Only",
            contextNotes: [],
            chatHistory: [],
            userQuery: "Hello"
        )

        #expect(messages.count >= 2) // System + User

        if let first = messages.first, case .system(let s) = first, case .textContent(let content) = s.content {
            #expect(content.contains("System Only"))
        } else {
             #expect(Bool(false), "First message should be system")
        }

        if let last = messages.last, case .user(let u) = last, case .string(let content) = u.content {
            #expect(content == "Hello")
        } else {
             #expect(Bool(false), "Last message should be user query")
        }
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
        // Original history is 10 messages. Plus 1 user query = 11.
        #expect(messages.count < largeHistory.count + 1)
        #expect(messages.last?.role == .user)  // User query always included
    }

    @Test("Test LLMService error when not configured")
    func unconfiguredServiceError() async throws {
        let service = LLMService()
        // No configuration provided

        await #expect(throws: LLMServiceError.notConfigured) {
            _ = try await service.sendMessage("Hello")
        }
    }

    @Test("Test generateTitle method")
    func titleGeneration() async throws {
        let mockClient = MockLLMClient()
        mockClient.nextResponse = "SwiftUI Basics"
        
        let service = LLMService(utilityClient: mockClient)
        
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

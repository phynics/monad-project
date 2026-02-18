import MonadShared
import Foundation
import OpenAI
import MonadCore
import MonadPrompt
import Testing

@Suite @MainActor
struct PromptIntegrationTests {

    @Test("testEmptyUserQueryDoesNotAppendMessage")
    func testEmptyUserQueryDoesNotAppendMessage() async throws {
        let service = LLMService(storage: MockConfigurationService())
        let history = [Message(content: "Hello", role: .user)]

        let prompt = await service.buildContext(
            userQuery: "",
            contextNotes: [],
            memories: [],
            chatHistory: history,
            tools: [],
            systemInstructions: nil
        )
        let messages = await prompt.toMessages()

        let userMessages = messages.filter {
            if case .user = $0 { return true }
            return false
        }

        // Should only contain the one from history (mapped as user)
        #expect(userMessages.count == 1)

        if let first = userMessages.first, case .user(let params) = first,
            case .string(let content) = params.content {
            #expect(content == "Hello")
        }
    }

    @Test("testNonEmptyUserQueryAppendsMessage")
    func testNonEmptyUserQueryAppendsMessage() async throws {
        let service = LLMService(storage: MockConfigurationService())
        let history = [Message(content: "Hello", role: .user)]

        let prompt = await service.buildContext(
            userQuery: "World",
            contextNotes: [],
            memories: [],
            chatHistory: history,
            tools: [],
            systemInstructions: nil
        )
        let messages = await prompt.toMessages()

        let userMessages = messages.filter {
            if case .user = $0 { return true }
            return false
        }

        #expect(userMessages.count == 2)
    }

    @Test("testUserQueryPreventsLeakageIntoSystem")
    func testUserQueryPreventsLeakageIntoSystem() async throws {
        let service = LLMService(storage: MockConfigurationService())
        let history = [Message(content: "Hi", role: .user)]
        let query = "UNIQUE_QUERY_STRING"

        let prompt = await service.buildContext(
            userQuery: query,
            contextNotes: [],
            memories: [],
            chatHistory: history,
            tools: [],
            systemInstructions: nil
        )
        let messages = await prompt.toMessages()

        guard let firstMsg = messages.first,
            case .system(let systemParam) = firstMsg,
            case .textContent(let systemContent) = systemParam.content
        else {
             // If no system message (empty instructions), then leakage is impossible in system message
            return
        }

        #expect(!systemContent.contains(query), "User query content leaked into system prompt")
    }
}

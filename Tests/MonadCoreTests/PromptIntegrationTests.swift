import Foundation
import MonadCore
import MonadPrompt
import MonadTestSupport
import OpenAI
import Testing

@Suite @MainActor
struct PromptIntegrationTests {
    @Test("testEmptyUserQueryDoesNotAppendMessage")
    func emptyUserQueryDoesNotAppendMessage() async {
        let service = LLMService(storage: MockConfigurationService())
        let history = [Message(content: "Hello", role: .user)]

        let prompt = await service.buildContext(
            userQuery: "",
            contextNotes: [],
            memories: [],
            chatHistory: history,
            tools: [],
            workspaces: [],
            primaryWorkspace: nil,
            clientName: nil,
            connectedClients: [],
            systemInstructions: nil
        )
        let messages = await prompt.toMessages()

        let userMessages = messages.filter {
            if case .user = $0 { return true }
            return false
        }

        // Should only contain the one from history (mapped as user)
        #expect(userMessages.count == 1)

        if let first = userMessages.first, case let .user(params) = first,
           case let .string(content) = params.content
        {
            #expect(content == "Hello")
        }
    }

    @Test("testNonEmptyUserQueryAppendsMessage")
    func nonEmptyUserQueryAppendsMessage() async {
        let service = LLMService(storage: MockConfigurationService())
        let history = [Message(content: "Hello", role: .user)]

        let prompt = await service.buildContext(
            userQuery: "World",
            contextNotes: [],
            memories: [],
            chatHistory: history,
            tools: [],
            workspaces: [],
            primaryWorkspace: nil,
            clientName: nil,
            connectedClients: [],
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
    func userQueryPreventsLeakageIntoSystem() async {
        let service = LLMService(storage: MockConfigurationService())
        let history = [Message(content: "Hi", role: .user)]
        let query = "UNIQUE_QUERY_STRING"

        let prompt = await service.buildContext(
            userQuery: query,
            contextNotes: [],
            memories: [],
            chatHistory: history,
            tools: [],
            workspaces: [],
            primaryWorkspace: nil,
            clientName: nil,
            connectedClients: [],
            systemInstructions: nil
        )
        let messages = await prompt.toMessages()

        guard let firstMsg = messages.first,
              case let .system(systemParam) = firstMsg,
              case let .textContent(systemContent) = systemParam.content
        else {
            // If no system message (empty instructions), then leakage is impossible in system message
            return
        }

        #expect(!systemContent.contains(query), "User query content leaked into system prompt")
    }
}

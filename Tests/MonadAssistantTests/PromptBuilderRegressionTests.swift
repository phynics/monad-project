import Foundation
import OpenAI
import Testing

@testable import MonadAssistant

@Suite @MainActor
struct PromptBuilderRegressionTests {

    @Test("testEmptyUserQueryDoesNotAppendMessage")
    func testEmptyUserQueryDoesNotAppendMessage() async throws {
        let builder = PromptBuilder()
        let history = [Message(content: "Hello", role: .user)]

        let (messages, _) = await builder.buildPrompt(
            contextNotes: [],
            chatHistory: history,
            userQuery: ""
        )

        let userMessages = messages.filter {
            if case .user = $0 { return true }
            return false
        }

        // Should only contain the one from history
        #expect(userMessages.count == 1)

        if let first = userMessages.first, case .user(let params) = first,
            case .string(let content) = params.content
        {
            #expect(content == "Hello")
        }
    }

    @Test("testNonEmptyUserQueryAppendsMessage")
    func testNonEmptyUserQueryAppendsMessage() async throws {
        let builder = PromptBuilder()
        let history = [Message(content: "Hello", role: .user)]

        let (messages, _) = await builder.buildPrompt(
            contextNotes: [],
            chatHistory: history,
            userQuery: "World"
        )

        let userMessages = messages.filter {
            if case .user = $0 { return true }
            return false
        }

        #expect(userMessages.count == 2)
    }

    @Test("testUserQueryPreventsLeakageIntoSystem")
    func testUserQueryPreventsLeakageIntoSystem() async throws {
        let builder = PromptBuilder()
        let history = [Message(content: "Hi", role: .user)]
        let query = "UNIQUE_QUERY_STRING"

        let (messages, _) = await builder.buildPrompt(
            contextNotes: [],
            chatHistory: history,
            userQuery: query
        )

        guard let firstMsg = messages.first,
            case .system(let systemParam) = firstMsg,
            case .textContent(let systemContent) = systemParam.content
        else {
            // It's acceptable if there is NO system message if instructions are empty,
            // but DefaultInstructions usually adds one.
            return
        }

        #expect(!systemContent.contains(query), "User query content leaked into system prompt")
    }
}

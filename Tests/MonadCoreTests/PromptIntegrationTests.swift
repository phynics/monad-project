import Foundation
import MonadCore
import MonadPrompt
import MonadShared
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
           case let .string(content) = params.content {
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
            systemInstructions: nil
        )
        let messages = await prompt.toMessages()

        let userMessages = messages.filter {
            if case .user = $0 { return true }
            return false
        }

        #expect(userMessages.count == 2)
    }

    // MARK: - Workspace Section

    @Test("workspaceSectionOmitsConnectionStatus")
    func workspaceSectionOmitsConnectionStatus() async {
        let uri = WorkspaceURI(host: "test-host", path: "/projects/test")
        let activeWS = WorkspaceReference(uri: uri, hostType: .client, status: .active)
        let missingWS = WorkspaceReference(uri: uri, hostType: .client, status: .missing)

        let sectionActive = WorkspacesContext(
            workspaces: [activeWS], primaryWorkspace: nil, clientName: nil
        )
        let sectionMissing = WorkspacesContext(
            workspaces: [missingWS], primaryWorkspace: nil, clientName: nil
        )

        let outputActive = await sectionActive.render() ?? ""
        let outputMissing = await sectionMissing.render() ?? ""

        #expect(!outputActive.contains("Connected"), "Active workspace should not show connection status")
        #expect(!outputActive.contains("Disconnected"), "Active workspace should not show connection status")
        #expect(!outputMissing.contains("Connected"), "Missing workspace should not show connection status")
        #expect(!outputMissing.contains("Disconnected"), "Missing workspace should not show connection status")
        #expect(outputActive.contains("Client"), "Workspace environment label should still appear")
    }

    @Test("userQueryPreventsLeakageIntoSystem")
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

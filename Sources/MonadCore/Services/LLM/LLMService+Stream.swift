import Foundation
import MonadShared
import OpenAI

public extension LLMServiceProtocol {
    /// Stream chat with full prompt building (includes notes, history, etc.)
    func chatStreamWithContext(_ request: LLMChatRequest) async -> LLMStreamResult {
        let promptRequest = LLMPromptRequest(
            userQuery: request.userQuery,
            contextNotes: request.contextNotes,
            memories: request.memories,
            chatHistory: request.chatHistory,
            tools: request.tools,
            workspaces: request.workspaces,
            primaryWorkspace: request.primaryWorkspace,
            clientName: request.clientName,
            systemInstructions: request.systemInstructions
        )
        let prompt = PromptBuilder.buildContext(promptRequest)

        // Convert to OpenAI format
        let messages = await prompt.toMessages()
        let rawPrompt = await prompt.render()

        // Delegate to client for streaming
        let toolParams = request.tools.isEmpty ? nil : request.tools.map { $0.toToolParam() }
        let stream = await chatStream(
            messages: messages,
            tools: toolParams,
            responseFormat: request.responseFormat,
            useUtilityModel: false,
            useFastModel: request.useFastModel
        )

        return LLMStreamResult(stream: stream, rawPrompt: rawPrompt)
    }
}

extension LLMService {
    /// Stream chat responses (low-level API)
    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?,
        useUtilityModel: Bool,
        useFastModel: Bool
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        let selectedClient: (any LLMClientProtocol)?
        if useFastModel {
            selectedClient = getFastClient() ?? getClient()
        } else if useUtilityModel {
            selectedClient = getUtilityClient() ?? getClient()
        } else {
            selectedClient = getClient()
        }

        guard let client = selectedClient else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
        }

        return await client.chatStream(
            messages: messages, tools: tools, responseFormat: responseFormat
        )
    }
}

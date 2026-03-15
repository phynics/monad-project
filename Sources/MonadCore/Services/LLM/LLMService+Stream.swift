import Foundation
import MonadShared
import OpenAI

public extension LLMService {
    /// Stream chat with full prompt building (includes notes, history, etc.)
    func chatStreamWithContext(_ request: LLMChatRequest) async -> LLMStreamResult {
        let clientToUse = request.useFastModel ? (getFastClient() ?? getClient()) : getClient()

        guard let client = clientToUse else {
            let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
            return LLMStreamResult(stream: stream, rawPrompt: "Error: Not configured", structuredContext: [:])
        }

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
        let prompt = await buildContext(promptRequest)

        // Convert to OpenAI format
        let messages = await prompt.toMessages()
        let rawPrompt = await prompt.render()
        let structuredContext = await prompt.structuredContext()

        // Delegate to client for streaming
        let toolParams = request.tools.isEmpty ? nil : request.tools.map { $0.toToolParam() }
        let stream = await client.chatStream(
            messages: messages, tools: toolParams, responseFormat: request.responseFormat
        )

        return LLMStreamResult(stream: stream, rawPrompt: rawPrompt, structuredContext: structuredContext)
    }

    /// Stream chat responses (low-level API)
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        guard let client = getClient() else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
        }

        return await client.chatStream(
            messages: messages, tools: tools, responseFormat: responseFormat
        )
    }
}

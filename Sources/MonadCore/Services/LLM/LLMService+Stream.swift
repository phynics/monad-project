import Foundation
import OpenAI

extension LLMService {
    /// Stream chat with full prompt building (includes notes, history, etc.)
    /// Returns tuple of (stream, rawPrompt for debug)
    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory] = [],
        chatHistory: [Message],
        tools: [any Tool],
        systemInstructions: String? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil,
        useFastModel: Bool = false
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let clientToUse = useFastModel ? (getFastClient() ?? getClient()) : getClient()

        guard let client = clientToUse else {
            let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
            return (stream, "Error: Not configured", [:])
        }

        // Build prompt with all components
        let (messages, rawPrompt, structuredContext) = await promptBuilder.buildPrompt(
            systemInstructions: systemInstructions,
            contextNotes: contextNotes,
            memories: memories,
            tools: tools,
            chatHistory: chatHistory,
            userQuery: userQuery
        )

        // Delegate to client for streaming
        let toolParams = tools.isEmpty ? nil : tools.map { $0.toToolParam() }
        let stream = await client.chatStream(
            messages: messages, tools: toolParams, responseFormat: responseFormat)

        return (stream, rawPrompt, structuredContext)
    }

    /// Stream chat responses (low-level API)
    /// Stream chat responses (low-level API)
    public func chatStream(
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
            messages: messages, tools: tools, responseFormat: responseFormat)
    }
}

import Foundation
import OpenAI

extension LLMService {
    /// Stream chat with full prompt building (includes notes, history, etc.)
    /// Returns tuple of (stream, rawPrompt for debug)
    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext] = [],
        memories: [Memory] = [],
        chatHistory: [Message],
        tools: [Tool] = [],
        systemInstructions: String? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) async -> (stream: AsyncThrowingStream<ChatStreamResult, Error>, rawPrompt: String) {
        guard let client = getClient() else {
            let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
            return (stream, "Error: Not configured")
        }

        // Build prompt with all components
        let (messages, rawPrompt) = await promptBuilder.buildPrompt(
            systemInstructions: systemInstructions,
            contextNotes: contextNotes,
            documents: documents,
            memories: memories,
            tools: tools,
            chatHistory: chatHistory,
            userQuery: userQuery
        )

        // Delegate to client for streaming
        let toolParams = tools.isEmpty ? nil : tools.map { $0.toToolParam() }
        let stream = await client.chatStream(messages: messages, tools: toolParams, responseFormat: responseFormat)

        return (stream, rawPrompt)
    }

    /// Stream chat responses (low-level API)
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        guard let client = getClient() else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
        }

        return await client.chatStream(messages: messages, tools: nil, responseFormat: responseFormat)
    }
}

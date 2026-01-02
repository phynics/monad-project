import Foundation
import OpenAI
import os.log

extension LLMService {
    /// Stream chat with full prompt building (includes notes, history, etc.)
    /// Returns tuple of (stream, rawPrompt for debug)
    func chatStreamWithContext(
        userQuery: String,
        contextNotes: [Note],
        chatHistory: [Message],
        tools: [Tool] = [],
        systemInstructions: String? = nil
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
            tools: tools,
            chatHistory: chatHistory,
            userQuery: userQuery
        )

        // Delegate to client for streaming
        let toolParams = tools.isEmpty ? nil : tools.map { $0.toToolParam() }
        let stream = await client.chatStream(messages: messages, tools: toolParams)

        return (stream, rawPrompt)
    }

    /// Stream chat responses (low-level API)
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam]
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        guard let client = getClient() else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
        }

        return await client.chatStream(messages: messages, tools: nil)
    }
}

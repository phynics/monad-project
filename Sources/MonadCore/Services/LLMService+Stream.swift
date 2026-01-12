import Foundation
import OpenAI

extension LLMService {
    /// Stream chat with full prompt building (includes notes, history, etc.)
    /// Returns tuple of (stream, rawPrompt for debug)
    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext],
        memories: [Memory],
        databaseDirectory: [TableDirectoryEntry],
        chatHistory: [Message],
        tools: [Tool],
        systemInstructions: String? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil,
        useFastModel: Bool = false
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>, 
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let (messages, rawPrompt, structuredContext) = await buildPrompt(
            userQuery: userQuery,
            contextNotes: contextNotes,
            documents: documents,
            memories: memories,
            databaseDirectory: databaseDirectory,
            chatHistory: chatHistory,
            tools: tools,
            systemInstructions: systemInstructions
        )

        // Delegate to client for streaming
        let toolParams = tools.isEmpty ? nil : tools.map { $0.toToolParam() }
        
        let selectedClient: (any LLMClientProtocol)?
        if useFastModel {
            selectedClient = fastClient ?? client
        } else {
            selectedClient = client
        }
        
        guard let llmClient = selectedClient else {
            return (
                stream: AsyncThrowingStream { continuation in
                    continuation.finish(throwing: LLMServiceError.notConfigured)
                },
                rawPrompt: rawPrompt,
                structuredContext: structuredContext
            )
        }
        
        let stream = await llmClient.chatStream(messages: messages, tools: toolParams, responseFormat: responseFormat)

        return (stream, rawPrompt, structuredContext)
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

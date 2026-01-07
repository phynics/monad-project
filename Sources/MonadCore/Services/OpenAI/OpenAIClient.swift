import Foundation
import OpenAI

/// A wrapper around the OpenAI SDK that provides a clean interface for the Monad Assistant
public actor OpenAIClient {
    private let client: OpenAI
    private let modelName: String

    public init(
        apiKey: String,
        modelName: String = "gpt-4o",
        host: String = "api.openai.com",
        port: Int = 443,
        scheme: String = "https"
    ) {
        let configuration = OpenAI.Configuration(
            token: apiKey,
            host: host,
            port: port,
            scheme: scheme
        )
        self.client = OpenAI(configuration: configuration)
        self.modelName = modelName
    }

    /// Stream chat responses
    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) -> AsyncThrowingStream<ChatStreamResult, Error> {
        let query = ChatQuery(
            messages: messages,
            model: modelName,
            responseFormat: responseFormat,
            tools: tools,
            streamOptions: .init(includeUsage: true)
        )

        return AsyncThrowingStream { continuation in
            let client = self.client
            Task {
                do {
                    for try await result in client.chatsStream(query: query) {
                        continuation.yield(result)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

// MARK: - Convenience Extensions

extension OpenAIClient {
    /// Simple helper to send a user message via stream (collects all content)
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat? = nil) async throws -> String {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user(.init(content: .string(content)))
        ]

        var fullContent = ""
        for try await result in chatStream(messages: messages, responseFormat: responseFormat) {
            if let delta = result.choices.first?.delta.content {
                fullContent += delta
            }
        }
        return fullContent
    }
}

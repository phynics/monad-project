import MonadShared
import Foundation
import OpenAI
import Logging

/// A wrapper around the OpenAI SDK that provides a clean interface for the Monad Assistant
public actor OpenAIClient {
    private let client: OpenAI
    private let modelName: String
    private let timeoutInterval: TimeInterval
    private let maxRetries: Int
    private let logger = Logger(label: "com.monad.openai-client")

    public init(
        apiKey: String,
        modelName: String = "gpt-4o",
        host: String = "api.openai.com",
        port: Int = 443,
        scheme: String = "https",
        timeoutInterval: TimeInterval = 60.0,
        maxRetries: Int = 3
    ) {
        let configuration = OpenAI.Configuration(
            token: apiKey,
            host: host,
            port: port,
            scheme: scheme,
            timeoutInterval: timeoutInterval
        )
        self.client = OpenAI(configuration: configuration)
        self.modelName = modelName
        self.timeoutInterval = timeoutInterval
        self.maxRetries = maxRetries
        logger.debug("Initialized OpenAIClient with model: \(modelName), host: \(host), port: \(port), scheme: \(scheme), timeout: \(timeoutInterval)s, maxRetries: \(maxRetries)")
    }

    /// Stream chat responses
    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) -> AsyncThrowingStream<ChatStreamResult, Error> {
        // Capture dependencies locally to avoid actor isolation issues in the stream closure
        let client = self.client
        let logger = self.logger
        let maxRetries = self.maxRetries
        let modelName = self.modelName

        let query = ChatQuery(
            messages: messages,
            model: modelName,
            responseFormat: responseFormat,
            tools: tools,
            streamOptions: .init(includeUsage: true)
        )

        logger.debug("Starting chat stream with model: \(modelName)")
        if let tools = tools {
            logger.debug("Tools provided: \(tools.map { $0.function.name }.joined(separator: ", "))")
        }

        return AsyncThrowingStream { continuation in
            Task {
                let hasYielded = Locked(false)

                do {
                    try await RetryPolicy.retry(
                        maxRetries: maxRetries,
                        shouldRetry: { error in
                            // Only retry if we haven't started yielding data to avoid duplication
                            // and if the error is transient
                            return !hasYielded.value && RetryPolicy.isTransient(error: error)
                        }
                    ) {
                        // Create a new stream for each attempt
                        let stream: AsyncThrowingStream<ChatStreamResult, Error> = client.chatsStream(query: query)

                        for try await result in stream {
                            if let delta = result.choices.first?.delta.content {
                                if !delta.isEmpty {
                                    hasYielded.value = true
                                    logger.debug("Yielding OpenAI chunk (\(delta.count) chars)")
                                }
                            }
                            // Also mark as yielded if we get tool calls or other content
                            if result.choices.first?.delta.toolCalls != nil {
                                hasYielded.value = true
                            }

                            continuation.yield(result)
                        }
                    }

                    logger.debug("OpenAI stream finished normally")
                    continuation.finish()
                } catch {
                    logger.error("OpenAI stream error: \(error.localizedDescription)")
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
        // We wrap the entire operation in retry because for a non-streaming result,
        // we can retry even if it failed midway (as we discard the partial result).
        // Capture maxRetries to avoid actor isolation issues in closure
        let maxRetries = self.maxRetries

        return try await RetryPolicy.retry(maxRetries: maxRetries) {
            let messages: [ChatQuery.ChatCompletionMessageParam] = [
                .user(.init(content: .string(content)))
            ]

            var fullContent = ""
            // We use the chatStream implementation, but here we don't mind if it fails mid-stream
            // because we are collecting it. However, chatStream's internal retry logic
            // stops retrying if it yielded. So if chatStream throws mid-stream,
            // THIS retry block will catch it and retry the whole thing.
            for try await result in await self.chatStream(messages: messages, responseFormat: responseFormat) {
                if let delta = result.choices.first?.delta.content {
                    fullContent += delta
                }
            }
            return fullContent
        }
    }

    /// Fetch available models from the service
    public func fetchAvailableModels() async throws -> [String]? {
        let maxRetries = self.maxRetries
        return try await RetryPolicy.retry(maxRetries: maxRetries) {
            let models = try await self.client.models()
            return models.data.map { $0.id }
        }
    }
}

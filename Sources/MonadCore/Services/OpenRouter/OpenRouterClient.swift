import Foundation
import OpenAI
import Logging

/// A specialized client for OpenRouter that handles their specific model discovery API
/// and ensures the correct /api/v1 path prefix is used for OpenAI compatibility.
public actor OpenRouterClient: Sendable {
    private let apiKey: String
    private let modelName: String
    private let endpoint: URL
    private let timeoutInterval: TimeInterval
    private let maxRetries: Int
    private let logger = Logger(label: "com.monad.openrouter-client")
    private let session: URLSession

    public init(
        apiKey: String,
        modelName: String = "openai/gpt-4o",
        host: String = "openrouter.ai",
        port: Int = 443,
        scheme: String = "https",
        timeoutInterval: TimeInterval = 60.0,
        maxRetries: Int = 3
    ) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.timeoutInterval = timeoutInterval
        self.maxRetries = maxRetries
        
        // OpenRouter base URL is usually https://openrouter.ai/api
        // We ensure we have the base domain and /api path
        var urlString = "\(scheme)://\(host)"
        if port != 443 && port != 80 {
            urlString += ":\(port)"
        }
        
        // If the host didn't already include /api, we might need it
        // But usually the host from LLMService is just the domain
        if !urlString.contains("/api") {
            urlString += "/api"
        }
        
        self.endpoint = URL(string: urlString)!
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        self.session = URLSession(configuration: config)
        logger.debug("Initialized OpenRouterClient with model: \(modelName), endpoint: \(urlString), timeout: \(timeoutInterval)s")
    }

    /// Stream chat responses using direct URLSession bytes stream
    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) -> AsyncThrowingStream<ChatStreamResult, Error> {
        // Capture dependencies
        let session = self.session
        let endpoint = self.endpoint
        let apiKey = self.apiKey
        let modelName = self.modelName
        let logger = self.logger
        let maxRetries = self.maxRetries

        let chatURL = endpoint.appendingPathComponent("v1/chat/completions")
        logger.debug("OpenRouter chat stream started for model: \(modelName) at \(chatURL.absoluteString)")
        
        return AsyncThrowingStream { continuation in
            Task {
                var hasYielded = false

                do {
                    try await RetryPolicy.retry(
                        maxRetries: maxRetries,
                        shouldRetry: { error in
                            return !hasYielded && RetryPolicy.isTransient(error: error)
                        }
                    ) {
                        var request = URLRequest(url: chatURL)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.setValue("https://github.com/monad-assistant/monad", forHTTPHeaderField: "HTTP-Referer")
                        request.setValue("Monad Assistant", forHTTPHeaderField: "X-Title")

                        // Map OpenAI parameters to a dictionary for JSON encoding
                        // We reuse the library's types but encode them manually to ensure control
                        let query = ChatQuery(
                            messages: messages,
                            model: modelName,
                            responseFormat: responseFormat,
                            tools: tools,
                            stream: true,
                            streamOptions: .init(includeUsage: true)
                        )

                        request.httpBody = try JSONEncoder().encode(query)

                        let (stream, response) = try await session.bytes(for: request)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw LLMServiceError.networkError("Invalid response type from OpenRouter")
                        }
                        
                        logger.debug("OpenRouter response status: \(httpResponse.statusCode)")

                        guard (200...299).contains(httpResponse.statusCode) else {
                            var errorBody = ""
                            for try await line in stream.lines {
                                errorBody += line
                            }
                            logger.error("OpenRouter error body: \(errorBody)")
                            throw LLMServiceError.networkError("OpenRouter API Error: \(httpResponse.statusCode) - \(errorBody)")
                        }

                        for try await line in stream.lines {
                            let trimmed = line.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { continue }
                            
                            // OpenRouter (OpenAI format) lines start with "data: "
                            if trimmed.hasPrefix("data: ") {
                                let dataString = String(trimmed.dropFirst(6))
                                if dataString == "[DONE]" {
                                    break
                                }

                                if let data = dataString.data(using: .utf8) {
                                    do {
                                        let result = try JSONDecoder().decode(ChatStreamResult.self, from: data)
                                        // Mark as yielded if we have content or tool calls
                                        if let content = result.choices.first?.delta.content, !content.isEmpty {
                                            hasYielded = true
                                        }
                                        if result.choices.first?.delta.toolCalls != nil {
                                            hasYielded = true
                                        }

                                        continuation.yield(result)
                                    } catch {
                                        logger.error("Failed to decode OpenRouter chunk: \(error.localizedDescription). Raw: \(dataString)")
                                    }
                                }
                            }
                        }
                    }
                    
                    logger.debug("OpenRouter stream finished normally")
                    continuation.finish()
                } catch {
                    logger.error("OpenRouter stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Send a single message (collects all content from stream)
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat? = nil) async throws -> String {
        let maxRetries = self.maxRetries

        return try await RetryPolicy.retry(maxRetries: maxRetries) {
            let messages: [ChatQuery.ChatCompletionMessageParam] = [
                .user(.init(content: .string(content)))
            ]

            var fullContent = ""
            for try await result in self.chatStream(messages: messages, responseFormat: responseFormat) {
                if let delta = result.choices.first?.delta.content {
                    fullContent += delta
                }
            }
            return fullContent
        }
    }

    /// Fetch available models from OpenRouter's specific models API
    public func fetchAvailableModels() async throws -> [String]? {
        let maxRetries = self.maxRetries
        let endpoint = self.endpoint
        let session = self.session
        let logger = self.logger
        
        return try await RetryPolicy.retry(maxRetries: maxRetries) {
            let url = endpoint.appendingPathComponent("v1/models")
            let request = URLRequest(url: url)
            logger.debug("Fetching OpenRouter models from: \(url.absoluteString)")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMServiceError.networkError("Invalid response type from OpenRouter models API")
            }

            logger.debug("OpenRouter models response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                throw LLMServiceError.networkError("OpenRouter API Error: \(httpResponse.statusCode)")
            }

            struct OpenRouterModelsResponse: Codable {
                struct Model: Codable {
                    let id: String
                }
                let data: [Model]
            }

            let modelsResponse = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
            let models = modelsResponse.data.map { $0.id }.sorted()
            logger.debug("Found \(models.count) OpenRouter models")
            return models
        }
    }
}

// Conform to the internal protocol
extension OpenRouterClient: LLMClientProtocol {}

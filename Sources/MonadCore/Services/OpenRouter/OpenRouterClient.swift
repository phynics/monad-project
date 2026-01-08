import Foundation
import OpenAI
import OSLog

/// A specialized client for OpenRouter that handles their specific model discovery API
public actor OpenRouterClient: Sendable {
    private let openAIClient: OpenAIClient
    private let logger = Logger(subsystem: "com.monad.assistant", category: "openrouter-client")
    private let session: URLSession

    public init(
        apiKey: String,
        modelName: String = "openai/gpt-4o",
        host: String = "openrouter.ai",
        port: Int = 443,
        scheme: String = "https"
    ) {
        // OpenRouter uses /api/v1 for its OpenAI-compatible endpoints
        // Most OpenAI SDKs allow setting the host, but some append /v1 automatically.
        // For MacPaw/OpenAI, we set the host to "openrouter.ai/api" if we want it to hit /api/v1
        
        self.openAIClient = OpenAIClient(
            apiKey: apiKey,
            modelName: modelName,
            host: "\(host)/api",
            port: port,
            scheme: scheme
        )
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        logger.debug("Initialized OpenRouterClient with model: \(modelName), host: \(host)")
    }

    /// Stream chat responses using the underlying OpenAIClient
    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        logger.debug("OpenRouter chat stream started")
        return await openAIClient.chatStream(messages: messages, tools: tools, responseFormat: responseFormat)
    }

    /// Send a single message using the underlying OpenAIClient
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat? = nil) async throws -> String {
        logger.debug("OpenRouter sendMessage started")
        return try await openAIClient.sendMessage(content, responseFormat: responseFormat)
    }

    /// Fetch available models from OpenRouter's specific models API
    public func fetchAvailableModels() async throws -> [String]? {
        let url = URL(string: "https://openrouter.ai/api/v1/models")!
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

// Conform to the internal protocol
extension OpenRouterClient: LLMClientProtocol {}

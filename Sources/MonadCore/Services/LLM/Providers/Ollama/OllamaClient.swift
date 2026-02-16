import MonadShared
import Foundation
import Logging
import OpenAI

public actor OllamaClient {
    private let endpoint: URL
    private let modelName: String
    private let timeoutInterval: TimeInterval
    private let maxRetries: Int
    private let session: URLSession
    private let logger = Logger(label: "com.monad.ollama-client")

    public init(
        endpoint: String,
        modelName: String,
        timeoutInterval: TimeInterval = 120.0,
        maxRetries: Int = 3
    ) {
        var cleanEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanEndpoint.hasSuffix("/") {
            cleanEndpoint.removeLast()
        }
        if cleanEndpoint.hasSuffix("/api") {
            cleanEndpoint.removeLast(4)
        }
        
        self.endpoint = URL(string: cleanEndpoint) ?? URL(string: "http://localhost:11434")!
        self.modelName = modelName
        self.timeoutInterval = timeoutInterval
        self.maxRetries = maxRetries
        
        // Use a custom configuration with longer timeout for local network robustness
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval * 5
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
        logger.debug("Initialized OllamaClient with model: \(modelName), endpoint: \(self.endpoint.absoluteString), timeout: \(timeoutInterval)s")
    }

    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) -> AsyncThrowingStream<ChatStreamResult, Error> {
        logger.debug("Ollama chat stream started for model: \(self.modelName)")

        // Capture dependencies
        let session = self.session
        let maxRetries = self.maxRetries
        let logger = self.logger

        return AsyncThrowingStream { continuation in
            Task {
                let hasYielded = Locked(false)

                do {
                    try await RetryPolicy.retry(
                        maxRetries: maxRetries,
                        shouldRetry: { error in
                            return !hasYielded.value && RetryPolicy.isTransient(error: error)
                        }
                    ) {
                        // Access self safely inside Task (on actor).
                        // Since we are inside an escaping closure passed to RetryPolicy (which runs async),
                        // we must await actor-isolated methods.
                        let request = try await self.buildRequest(messages: messages, tools: tools, responseFormat: responseFormat)
                        logger.debug("Ollama request URL: \(request.url?.absoluteString ?? "nil")")
                        if let body = request.httpBody, let bodyString = String(data: body, encoding: .utf8) {
                            logger.debug("Ollama request body: \(bodyString)")
                        }

                        let (stream, response) = try await session.bytes(for: request)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw LLMServiceError.networkError("Invalid response type from Ollama")
                        }

                        logger.debug("Ollama response status code: \(httpResponse.statusCode)")

                        guard (200...299).contains(httpResponse.statusCode)
                        else {
                            // Attempt to read error body
                            var errorBody = ""
                            for try await line in stream.lines {
                                errorBody += line
                            }
                            logger.error("Ollama error response body: \(errorBody)")
                            throw LLMServiceError.networkError(
                                "Ollama API Error: \(httpResponse.statusCode) - \(errorBody)")
                        }

                        for try await line in stream.lines {
                            guard !line.isEmpty else { continue }
                            guard let data = line.data(using: .utf8) else { continue }

                            if let response = try? JSONDecoder().decode(
                                OllamaChatResponse.self, from: data)
                            {
                                if let converted = await self.convertToOpenAI(response) {
                                    // Check content or tool calls to mark yielded
                                    if let content = converted.choices.first?.delta.content, !content.isEmpty {
                                        hasYielded.value = true
                                    }
                                    if converted.choices.first?.delta.toolCalls != nil {
                                        hasYielded.value = true
                                    }

                                    logger.debug("Yielding Ollama chunk: \(converted.choices.first?.delta.content ?? "")")
                                    continuation.yield(converted)
                                }
                            }
                        }
                    }
                    logger.debug("Ollama stream finished normally")
                    continuation.finish()
                } catch {
                    logger.error("Ollama stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func buildRequest(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) throws -> URLRequest {
        let chatURL = endpoint.appendingPathComponent("api/chat")
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let ollamaMessages = messages.map { msg -> OllamaMessage in
            var role = "user"
            var content = ""

            switch msg {
            case .system(let m):
                role = "system"
                if case .textContent(let text) = m.content {
                    content = text
                } else {
                    content = "\(m.content)"
                }
            case .user(let m):
                role = "user"
                if case .string(let text) = m.content {
                    content = text
                } else {
                    content = "\(m.content)"
                }
            case .assistant(let m):
                role = "assistant"
                if let c = m.content {
                    if case .textContent(let text) = c {
                        content = text
                    } else {
                        content = "\(c)"
                    }
                } else {
                    content = ""
                }
            case .tool(let m):
                role = "tool"
                if case .textContent(let text) = m.content {
                    content = text
                } else {
                    content = "\(m.content)"
                }
            case .developer(let m):
                role = "system"
                if case .textContent(let text) = m.content {
                    content = text
                } else {
                    content = "\(m.content)"
                }
            }

            return OllamaMessage(role: role, content: content, tool_calls: nil)
        }

        var format: String? = nil
        if let responseFormat = responseFormat {
            switch responseFormat {
            case .jsonObject, .jsonSchema:
                format = "json"
            case .text:
                format = nil
            @unknown default:
                format = nil
            }
        }

        let payload = OllamaChatRequest(
            model: modelName,
            messages: ollamaMessages,
            stream: true,
            format: format,
            tools: tools?.map { tool in
                OllamaTool(
                    type: "function",
                    function: OllamaToolFunction(
                        name: tool.function.name,
                        description: tool.function.description ?? "",
                        parameters: tool.function.parameters ?? .object([:])
                    )
                )
            }
        )

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func convertToOpenAI(_ response: OllamaChatResponse) -> ChatStreamResult? {
        // Map Ollama tool calls to OpenAI format
        let openAIToolCalls = response.message.tool_calls?.enumerated().map { (index, tc) in
            [
                "index": index,
                "id": UUID().uuidString,
                "type": "function",
                "function": [
                    "name": tc.function.name,
                    "arguments": (try? tc.function.arguments.toJsonString()) ?? "{}"
                ]
            ]
        }

        // Handle final chunk with usage statistics
        if response.done {
            let promptEvalCount = response.prompt_eval_count ?? 0
            let evalCount = response.eval_count ?? 0
            
            var delta: [String: Any] = [
                "role": "assistant",
                "content": response.message.content
            ]
            
            if let tc = openAIToolCalls {
                delta["tool_calls"] = tc
            }

            let jsonDict: [String: Any] = [
                "id": UUID().uuidString,
                "object": "chat.completion.chunk",
                "created": Int(Date().timeIntervalSince1970),
                "model": response.model,
                "choices": [
                    [
                        "index": 0,
                        "delta": delta,
                        "finish_reason": response.message.tool_calls?.isEmpty == false ? "tool_calls" : "stop",
                    ]
                ],
                "usage": [
                    "prompt_tokens": promptEvalCount,
                    "completion_tokens": evalCount,
                    "total_tokens": promptEvalCount + evalCount
                ]
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: jsonDict)
                return try JSONDecoder().decode(ChatStreamResult.self, from: data)
            } catch {
                logger.error("Failed to convert final Ollama response: \(error)")
                return nil
            }
        }

        // Skip empty intermediate chunks WITHOUT tool calls
        guard !response.message.content.isEmpty || response.message.tool_calls?.isEmpty == false else {
            return nil
        }

        // Manually construct JSON for intermediate chunks
        var delta: [String: Any] = [
            "role": "assistant",
            "content": response.message.content,
        ]
        
        if let tc = openAIToolCalls {
            delta["tool_calls"] = tc
        }

        let jsonDict: [String: Any] = [
            "id": UUID().uuidString,
            "object": "chat.completion.chunk",
            "created": Int(Date().timeIntervalSince1970),
            "model": response.model,
            "choices": [
                [
                    "index": 0,
                    "delta": delta,
                    "finish_reason": nil,
                ]
            ],
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: jsonDict)
            return try JSONDecoder().decode(ChatStreamResult.self, from: data)
        } catch {
            logger.error("Failed to convert Ollama response to OpenAI: \(error)")
            return nil
        }
    }

    // Simple helper
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat? = nil) async throws -> String {
        let maxRetries = self.maxRetries
        return try await RetryPolicy.retry(maxRetries: maxRetries) {
            let messages: [ChatQuery.ChatCompletionMessageParam] = [
                .user(.init(content: .string(content)))
            ]

            var fullContent = ""
            // chatStream is actor-isolated, so we must await it to get the stream
            for try await result in await self.chatStream(messages: messages, responseFormat: responseFormat) {
                if let delta = result.choices.first?.delta.content {
                    fullContent += delta
                }
            }
            return fullContent
        }
    }

    public func fetchAvailableModels() async throws -> [String]? {
        let maxRetries = self.maxRetries
        let endpoint = self.endpoint
        let session = self.session
        let logger = self.logger

        return try await RetryPolicy.retry(maxRetries: maxRetries) {
            let tagsURL = endpoint.appendingPathComponent("api/tags")
            let request = URLRequest(url: tagsURL)
            logger.debug("Fetching Ollama models from: \(tagsURL.absoluteString)")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw LLMServiceError.networkError("Invalid response type from Ollama models API")
            }

            logger.debug("Ollama models response status: \(httpResponse.statusCode)")

            guard (200...299).contains(httpResponse.statusCode) else {
                throw LLMServiceError.networkError("Ollama API Error: \(httpResponse.statusCode)")
            }

            struct OllamaTagsResponse: Codable {
                struct Model: Codable {
                    let name: String
                }
                let models: [Model]
            }

            let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
            let models = tagsResponse.models.map { $0.name }
            logger.debug("Found \(models.count) Ollama models: \(models.joined(separator: ", "))")
            return models
        }
    }
}

// MARK: - Internal Models

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let format: String?
    let tools: [OllamaTool]?
}

struct OllamaTool: Codable {
    let type: String
    let function: OllamaToolFunction
}

struct OllamaToolFunction: Codable {
    let name: String
    let description: String
    let parameters: JSONSchema
}

struct OllamaMessage: Codable {
    let role: String
    let content: String
    let tool_calls: [OllamaToolCall]?
}

struct OllamaToolCall: Codable {
    let function: OllamaToolCallFunction
}

struct OllamaToolCallFunction: Codable {
    let name: String
    let arguments: [String: AnyCodable]
}

struct OllamaChatResponse: Codable {
    let model: String
    let created_at: String?
    let message: OllamaMessage
    let done: Bool
    let total_duration: Int64?
    let load_duration: Int64?
    let prompt_eval_count: Int?
    let eval_count: Int?
}

import Foundation
import OSLog
import OpenAI

public actor OllamaClient {
    private let endpoint: URL
    private let modelName: String
    private let session: URLSession
    private let logger = Logger(subsystem: "com.monad.assistant", category: "ollama-client")

    public init(
        endpoint: String,
        modelName: String
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
        
        // Use a custom configuration with longer timeout for local network robustness
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60 // 60 seconds
        config.timeoutIntervalForResource = 300 // 5 minutes
        // Enable wait for connectivity to handle transient network/resolution issues
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) -> AsyncThrowingStream<ChatStreamResult, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(messages: messages, tools: tools, responseFormat: responseFormat)

                    let (stream, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    else {
                        // Attempt to read error body
                        var errorBody = ""
                        for try await line in stream.lines {
                            errorBody += line
                        }
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw LLMServiceError.networkError(
                            "Ollama API Error: \(statusCode) - \(errorBody)")
                    }

                    for try await line in stream.lines {
                        guard !line.isEmpty else { continue }
                        guard let data = line.data(using: .utf8) else { continue }

                        if let response = try? JSONDecoder().decode(
                            OllamaChatResponse.self, from: data)
                        {
                            if let converted = convertToOpenAI(response) {
                                logger.debug("Yielding Ollama chunk: \(response.message.content)")
                                continuation.yield(converted)
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
            // Basic mapping
            // Note: OpenAI messages enum is complex, need to extract content.
            // Simplified for brevity, need full extraction logic usually.
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

            return OllamaMessage(role: role, content: content)
        }

        // Map responseFormat to Ollama's format parameter
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
            format: format
        )

        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    private func convertToOpenAI(_ response: OllamaChatResponse) -> ChatStreamResult? {
        guard !response.done else { return nil }

        // Manually construct JSON to decode into ChatStreamResult
        // This avoids private/internal init issues with the OpenAI library
        let jsonDict: [String: Any] = [
            "id": UUID().uuidString,
            "object": "chat.completion.chunk",
            "created": Date().timeIntervalSince1970,
            "model": response.model,
            "choices": [
                [
                    "index": 0,
                    "delta": [
                        "role": "assistant",
                        "content": response.message.content,
                    ],
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

    public func fetchAvailableModels() async throws -> [String]? {
        let tagsURL = endpoint.appendingPathComponent("api/tags")
        let request = URLRequest(url: tagsURL)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LLMServiceError.networkError("Ollama API Error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        
        struct OllamaTagsResponse: Codable {
            struct Model: Codable {
                let name: String
            }
            let models: [Model]
        }
        
        let tagsResponse = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        return tagsResponse.models.map { $0.name }
    }
}

// MARK: - Internal Models

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
    let format: String?
}

struct OllamaMessage: Codable {
    let role: String
    let content: String
}

struct OllamaChatResponse: Codable {
    let model: String
    let created_at: String?
    let message: OllamaMessage
    let done: Bool
}

import Foundation
import OSLog
import OpenAI

public actor OllamaClient {
    private let endpoint: URL
    private let modelName: String
    private let logger = Logger(subsystem: "com.monad.assistant", category: "ollama-client")

    public init(
        endpoint: String,
        modelName: String
    ) {
        self.endpoint = URL(string: endpoint) ?? URL(string: "http://localhost:11434")!
        self.modelName = modelName
    }

    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil
    ) -> AsyncThrowingStream<ChatStreamResult, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try buildRequest(messages: messages, tools: tools)

                    let (stream, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    else {
                        throw LLMServiceError.networkError(
                            "Ollama API Error: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
                    }

                    for try await line in stream.lines {
                        guard !line.isEmpty else { continue }
                        guard let data = line.data(using: .utf8) else { continue }

                        if let response = try? JSONDecoder().decode(
                            OllamaChatResponse.self, from: data)
                        {
                            if let converted = convertToOpenAI(response) {
                                continuation.yield(converted)
                            }
                        }
                    }
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
        tools: [ChatQuery.ChatCompletionToolParam]?
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

        // ... (request payload building) ...

        let payload = OllamaChatRequest(
            model: modelName,
            messages: ollamaMessages,
            stream: true
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
    public func sendMessage(_ content: String) async throws -> String {
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user(.init(content: .string(content)))
        ]

        var fullContent = ""
        for try await result in chatStream(messages: messages) {
            if let delta = result.choices.first?.delta.content {
                fullContent += delta
            }
        }
        return fullContent
    }
}

// MARK: - Internal Models

struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaMessage]
    let stream: Bool
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

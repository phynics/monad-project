import Foundation
import MonadShared
import OpenAI

// MARK: - API Models

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
    let toolCalls: [OllamaToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }
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
    let createdAt: String?
    let message: OllamaMessage
    let done: Bool
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let evalCount: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case message
        case done
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
    }
}

// MARK: - Helper Constructs

extension OllamaMessage {
    init(from param: ChatQuery.ChatCompletionMessageParam) {
        var role = "user"
        var content = ""

        switch param {
        case let .system(message):
            role = "system"
            if case let .textContent(text) = message.content {
                content = text
            } else {
                content = "\(message.content)"
            }
        case let .user(message):
            role = "user"
            if case let .string(text) = message.content {
                content = text
            } else {
                content = "\(message.content)"
            }
        case let .assistant(message):
            role = "assistant"
            if let messageContent = message.content {
                if case let .textContent(text) = messageContent {
                    content = text
                } else {
                    content = "\(messageContent)"
                }
            } else {
                content = ""
            }
        case let .tool(message):
            role = "tool"
            if case let .textContent(text) = message.content {
                content = text
            } else {
                content = "\(message.content)"
            }
        case let .developer(message):
            role = "system"
            if case let .textContent(text) = message.content {
                content = text
            } else {
                content = "\(message.content)"
            }
        }

        self.init(role: role, content: content, toolCalls: nil)
    }
}

extension OllamaTool {
    init(from tool: ChatQuery.ChatCompletionToolParam) {
        self.init(
            type: "function",
            function: OllamaToolFunction(
                name: tool.function.name,
                description: tool.function.description ?? "",
                parameters: tool.function.parameters ?? .object([:])
            )
        )
    }
}

struct OllamaEndpoint {
    let rawValue: String

    var url: URL {
        var cleanEndpoint = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanEndpoint.hasSuffix("/") {
            cleanEndpoint.removeLast()
        }
        if cleanEndpoint.hasSuffix("/api") {
            cleanEndpoint.removeLast(4)
        }

        if let url = URL(string: cleanEndpoint) {
            return url
        } else {
            return URL(string: "http://localhost:11434")!
        }
    }

    var chatURL: URL {
        url.appendingPathComponent("api/chat")
    }

    var tagsURL: URL {
        url.appendingPathComponent("api/tags")
    }
}

import Foundation
import OpenAI

// MARK: - OpenAI Model Extensions for Initialization
// These extensions provide public initializers for OpenAI models that only have internal ones or init(from: Decoder).
// This is necessary for gRPCLLMService to map gRPC responses back to OpenAI types used by the rest of the app.

extension ChatStreamResult {
    public init(
        id: String,
        choices: [Choice],
        created: TimeInterval,
        model: String,
        object: String = "chat.completion.chunk",
        systemFingerprint: String? = nil,
        usage: ChatResult.CompletionUsage? = nil
    ) {
        // Use JSON trick to initialize since the actual properties are let and only have internal init or Decodable
        let dict: [String: Any] = [
            "id": id,
            "choices": choices.map { choice -> [String: Any] in
                var choiceDict: [String: Any] = [
                    "index": choice.index,
                    "delta": [
                        "content": choice.delta.content as Any,
                        "role": choice.delta.role?.rawValue as Any
                    ]
                ]
                if let finishReason = choice.finishReason {
                    choiceDict["finish_reason"] = finishReason.rawValue
                }
                return choiceDict
            },
            "created": created,
            "model": model,
            "object": object,
            "system_fingerprint": systemFingerprint as Any,
            "usage": usage != nil ? [
                "completion_tokens": usage!.completionTokens,
                "prompt_tokens": usage!.promptTokens,
                "total_tokens": usage!.totalTokens
            ] : NSNull()
        ]
        
        let data = try! JSONSerialization.data(withJSONObject: dict)
        self = try! JSONDecoder().decode(ChatStreamResult.self, from: data)
    }
}

extension ChatStreamResult.Choice {
    public static func mock(index: Int, content: String?, think: String? = nil, role: ChatQuery.ChatCompletionMessageParam.Role? = .assistant, finishReason: FinishReason? = nil) -> ChatStreamResult.Choice {
        let dict: [String: Any] = [
            "index": index,
            "delta": [
                "content": content as Any,
                "reasoning": think as Any,
                "role": role?.rawValue as Any
            ],
            "finish_reason": finishReason?.rawValue as Any
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return try! JSONDecoder().decode(ChatStreamResult.Choice.self, from: data)
    }
}

extension ChatResult.CompletionUsage {
    public init(completionTokens: Int, promptTokens: Int, totalTokens: Int) {
        let dict: [String: Any] = [
            "completion_tokens": completionTokens,
            "prompt_tokens": promptTokens,
            "total_tokens": totalTokens
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        self = try! JSONDecoder().decode(ChatResult.CompletionUsage.self, from: data)
    }
}

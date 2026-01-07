import Foundation
import MonadCore
import OpenAI

final class MockEmbeddingService: EmbeddingService, @unchecked Sendable {
    var mockEmbedding: [Double] = [0.1, 0.2, 0.3]
    var lastInput: String?
    
    func generateEmbedding(for text: String) async throws -> [Double] {
        lastInput = text
        return mockEmbedding
    }
    
    func generateEmbeddings(for texts: [String]) async throws -> [[Double]] {
        return texts.map { _ in mockEmbedding }
    }
}

final class MockLLMClient: LLMClientProtocol, @unchecked Sendable {
    var nextResponse: String = ""
    var lastMessages: [ChatQuery.ChatCompletionMessageParam] = []
    
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        lastMessages = messages
        return AsyncThrowingStream { continuation in
            let jsonDict: [String: Any] = [
                "id": "mock",
                "object": "chat.completion.chunk",
                "created": Date().timeIntervalSince1970,
                "model": "mock-model",
                "choices": [
                    [
                        "index": 0,
                        "delta": [
                            "role": "assistant",
                            "content": nextResponse,
                        ],
                        "finish_reason": "stop",
                    ]
                ],
            ]
            
            do {
                let data = try JSONSerialization.data(withJSONObject: jsonDict)
                let result = try JSONDecoder().decode(ChatStreamResult.self, from: data)
                continuation.yield(result)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
    
    func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?) async throws -> String {
        lastMessages = [.user(.init(content: .string(content)))]
        return nextResponse
    }
}

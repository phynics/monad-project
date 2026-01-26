import Hummingbird
import Foundation
import MonadCore
import HTTPTypes
import NIOCore
import OpenAI

public struct ChatRequest: Codable, Sendable {
    public let message: String
    
    public init(message: String) {
        self.message = message
    }
}

public struct ChatResponse: Codable, Sendable, ResponseGenerator {
    public let response: String
    
    public init(response: String) {
        self.response = response
    }
    
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let data = try JSONEncoder().encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

public struct ChatController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    public let llmService: ServerLLMService
    
    public init(sessionManager: SessionManager, llmService: ServerLLMService) {
        self.sessionManager = sessionManager
        self.llmService = llmService
    }
    
    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/{id}/chat", use: chat)
        group.post("/{id}/chat/stream", use: chatStream)
    }
    
    @Sendable func chat(_ request: Request, context: Context) async throws -> ChatResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest, message: "Invalid Session ID")
        }
        
        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
        
        guard let _ = await sessionManager.getSession(id: id) else {
            throw HTTPError(.notFound, message: "Session not found")
        }
        
        // TODO: Use ContextManager to gather context
        // let contextManager = await sessionManager.getContextManager(for: id)
        
        let response = try await llmService.sendMessage(chatRequest.message)
        return ChatResponse(response: response)
    }
    
    @Sendable func chatStream(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest, message: "Invalid Session ID")
        }
        
        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
        
        guard let session = await sessionManager.getSession(id: id) else {
            throw HTTPError(.notFound, message: "Session not found")
        }
        
        // TODO: Context
        
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            .user(.init(content: .string(chatRequest.message)))
        ]
        
        let stream = try await llmService.chatStream(messages: messages)
        
        let sseStream = AsyncStream<ByteBuffer> { continuation in
            Task {
                do {
                    for try await result in stream {
                        if let data = try? JSONEncoder().encode(result) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    }
                    continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
        
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        
        return Response(status: .ok, headers: headers, body: .init(asyncSequence: sseStream))
    }
}

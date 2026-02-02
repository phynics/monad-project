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
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

public struct ChatController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    public let llmService: any LLMServiceProtocol
    
    public init(sessionManager: SessionManager, llmService: any LLMServiceProtocol) {
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
            throw HTTPError(.badRequest)
        }
        
        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
        
        guard let _ = await sessionManager.getSession(id: id) else {
            throw HTTPError(.notFound)
        }
        
        let persistence = await sessionManager.getPersistenceService()
        let contextManager = await sessionManager.getContextManager(for: id)
        
        // 1. Save User Message
        let userMsg = ConversationMessage(sessionId: id, role: .user, content: chatRequest.message)
        try await persistence.saveMessage(userMsg)
        
        // 2. Fetch History
        let history = try await sessionManager.getHistory(for: id)
        
        // 3. Gather Context
        var contextData = ContextData()
        if let contextManager = contextManager {
            contextData = try await contextManager.gatherContext(
                for: chatRequest.message,
                history: history,
                tagGenerator: { [llmService] query in
                    try await llmService.generateTags(for: query)
                }
            )
        }
        
        // 4. Send Message with Context
        guard await llmService.isConfigured else {
            throw HTTPError(.serviceUnavailable)
        }
        
        let (stream, _, _) = try await llmService.chatStreamWithContext(
            userQuery: chatRequest.message,
            contextNotes: contextData.notes,
            documents: [],
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: [],
            systemInstructions: nil,
            responseFormat: nil,
            useFastModel: false
        )
        
        var fullResponse = ""
        for try await result in stream {
            if let delta = result.choices.first?.delta.content {
                fullResponse += delta
            }
        }
        
                    // 5. Save Assistant Message
                    let recalledMemoriesData = try SerializationUtils.jsonEncoder.encode(contextData.memories.map { $0.memory })
                    let recalledMemoriesString = String(decoding: recalledMemoriesData, as: UTF8.self)        
        let assistantMsg = ConversationMessage(
            sessionId: id, 
            role: .assistant, 
            content: fullResponse,
            recalledMemories: recalledMemoriesString
        )
        try await persistence.saveMessage(assistantMsg)
        
        return ChatResponse(response: fullResponse)
    }
    
    @Sendable func chatStream(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }
        
        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
        
        guard let _ = await sessionManager.getSession(id: id) else {
            throw HTTPError(.notFound)
        }
        
        let persistence = await sessionManager.getPersistenceService()
        let contextManager = await sessionManager.getContextManager(for: id)
        
        // 1. Save User Message
        let userMsg = ConversationMessage(sessionId: id, role: .user, content: chatRequest.message)
        try await persistence.saveMessage(userMsg)
        
        // 2. Fetch History
        let history = try await sessionManager.getHistory(for: id)
        
        // 3. Gather Context
        var contextData = ContextData()
        if let contextManager = contextManager {
            contextData = try await contextManager.gatherContext(
                for: chatRequest.message,
                history: history,
                tagGenerator: { [llmService] query in
                    try await llmService.generateTags(for: query)
                }
            )
        }
        
        guard await llmService.isConfigured else {
            throw HTTPError(.serviceUnavailable)
        }
        
        let streamData = try await llmService.chatStreamWithContext(
            userQuery: chatRequest.message,
            contextNotes: contextData.notes,
            documents: [],
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: [],
            systemInstructions: nil,
            responseFormat: nil,
            useFastModel: false
        )
        
        let memories = contextData.memories.map { $0.memory }
        
        let sseStream = AsyncStream<ByteBuffer> { continuation in
            Task { [id, persistence, memories] in
                do {
                    var fullResponse = ""
                    for try await result in streamData.stream {
                        if let delta = result.choices.first?.delta.content {
                            fullResponse += delta
                        }
                                                    if let data = try? SerializationUtils.jsonEncoder.encode(result) {
                                                        let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                                                        continuation.yield(ByteBuffer(string: sseString))
                                                    }                    }
                    
                                            // 5. Save Assistant Message
                                            let recalledMemoriesData = try? SerializationUtils.jsonEncoder.encode(memories)
                                            let recalledMemoriesString = recalledMemoriesData.flatMap { String(decoding: $0, as: UTF8.self) } ?? "[]"                    
                    let assistantMsg = ConversationMessage(
                        sessionId: id, 
                        role: .assistant, 
                        content: fullResponse,
                        recalledMemories: recalledMemoriesString
                    )
                    try? await persistence.saveMessage(assistantMsg)
                    
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
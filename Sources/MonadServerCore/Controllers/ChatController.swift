import Hummingbird
import Foundation
import MonadCore
import HTTPTypes
import NIOCore

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
}

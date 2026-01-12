import Foundation
import GRPC
import MonadCore
import SwiftProtobuf
import OpenAI

final class ChatHandler: MonadChatServiceAsyncProvider {
    private let llm: LLMServiceProtocol
    private let persistence: PersistenceServiceProtocol
    
    init(llm: LLMServiceProtocol, persistence: PersistenceServiceProtocol) {
        self.llm = llm
        self.persistence = persistence
    }
    
    func chatStream(request: MonadChatRequest, responseStream: GRPCAsyncResponseStreamWriter<MonadChatResponse>, context: GRPCAsyncServerCallContext) async throws {
        // 1. Fetch relevant context from server-side persistence
        let history = request.history.map { Message(from: $0) }
        
        // Server-side tools
        let tools: [MonadCore.Tool] = [] 
        
        // Call LLM
        let (stream, _, _) = await llm.chatStreamWithContext(
            userQuery: request.userQuery,
            contextNotes: [], 
            documents: [],
            memories: [], 
            databaseDirectory: [],
            chatHistory: history,
            tools: tools,
            systemInstructions: request.hasSystemInstructions ? request.systemInstructions : nil,
            responseFormat: nil,
            useFastModel: request.useFastModel
        )
        
        for try await result in stream {
            var response = MonadChatResponse()
            
            // Map OpenAI ChatStreamResult to MonadChatResponse
            // ChatStreamResult has 'choices' and 'usage'
            if let choice = result.choices.first {
                if let content = choice.delta.content {
                    response.contentDelta = content
                }
                // Think tags might be in content delta, but MonadCore's parser handles them
                // If we want to separate deltas on the server, we'd need more logic.
                // For now, let's keep it simple.
                
                if let toolCalls = choice.delta.toolCalls, !toolCalls.isEmpty {
                    // TODO: Map tool calls if needed
                }
            }
            
            if let usage = result.usage {
                var grpcMeta = MonadChatResponse.Metadata()
                grpcMeta.model = result.model
                grpcMeta.promptTokens = Int32(usage.promptTokens)
                grpcMeta.completionTokens = Int32(usage.completionTokens)
                // Duration and TPS are not in ChatStreamResult
                response.metadata = grpcMeta
            }
            
            try await responseStream.send(response)
        }
    }
    
    func sendMessage(request: MonadChatRequest, context: GRPCAsyncServerCallContext) async throws -> MonadMessage {
        let response = try await llm.sendMessage(request.userQuery)
        var msg = MonadMessage()
        msg.content = response
        msg.role = .assistant
        msg.id = UUID().uuidString
        return msg
    }
    
    func generateTitle(request: MonadGenerateTitleRequest, context: GRPCAsyncServerCallContext) async throws -> MonadGenerateTitleResponse {
        let history = request.messages.map { Message(from: $0) }
        let title = try await llm.generateTitle(for: history)
        var response = MonadGenerateTitleResponse()
        response.title = title
        return response
    }
}
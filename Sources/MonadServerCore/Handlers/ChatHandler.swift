import Foundation
import GRPC
import SwiftProtobuf
import MonadCore
import OpenAI

public final class ChatHandler: MonadChatServiceAsyncProvider, Sendable {
    private let llm: any LLMServiceProtocol
    private let persistence: any PersistenceServiceProtocol
    
    public init(llm: any LLMServiceProtocol, persistence: any PersistenceServiceProtocol) {
        self.llm = llm
        self.persistence = persistence
    }
    
    public func chatStream(request: MonadChatRequest, responseStream: GRPCAsyncResponseStreamWriter<MonadChatResponse>, context: GRPCAsyncServerCallContext) async throws {
        try await chatStream(request: request, responseStream: responseStream, context: context as any MonadServerContext)
    }

    public func chatStream(request: MonadChatRequest, responseStream: GRPCAsyncResponseStreamWriter<MonadChatResponse>, context: any MonadServerContext) async throws {
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
                            if let choice = result.choices.first {
                                if let content = choice.delta.content {
                                    // Use Message.parseResponse logic to separate thinking
                                    // For stream deltas, we might need a more stateful approach if tags span chunks,
                                    // but for PoC we'll send as contentDelta.
                                    response.contentDelta = content
                                }
                                
                                if let think = choice.delta.reasoning {
                                    response.thinkDelta = think
                                }
                                
                                if let toolCalls = choice.delta.toolCalls, !toolCalls.isEmpty {
                                    // TODO: Map tool calls if needed
                                }
                            }            
            if let usage = result.usage {
                var grpcMeta = MonadChatResponse.Metadata()
                grpcMeta.model = result.model
                grpcMeta.promptTokens = Int32(usage.promptTokens)
                grpcMeta.completionTokens = Int32(usage.completionTokens)
                response.metadata = grpcMeta
            }
            
            try await responseStream.send(response)
        }
    }
    
    public func sendMessage(request: MonadChatRequest, context: GRPCAsyncServerCallContext) async throws -> MonadMessage {
        return try await sendMessage(request: request, context: context as any MonadServerContext)
    }

    public func sendMessage(request: MonadChatRequest, context: any MonadServerContext) async throws -> MonadMessage {
        let response = try await llm.sendMessage(request.userQuery)
        var msg = MonadMessage()
        msg.content = response
        msg.role = .assistant
        msg.id = UUID().uuidString
        return msg
    }
    
    public func generateTitle(request: MonadGenerateTitleRequest, context: GRPCAsyncServerCallContext) async throws -> MonadGenerateTitleResponse {
        return try await generateTitle(request: request, context: context as any MonadServerContext)
    }

    public func generateTitle(request: MonadGenerateTitleRequest, context: any MonadServerContext) async throws -> MonadGenerateTitleResponse {
        let history = request.messages.map { Message(from: $0) }
        let title = try await llm.generateTitle(for: history)
        var response = MonadGenerateTitleResponse()
        response.title = title
        return response
    }
}
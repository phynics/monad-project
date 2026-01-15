import Foundation
import GRPC
import NIOCore
import NIOPosix
import SwiftProtobuf
import OpenAI

@MainActor
public final class gRPCLLMService: LLMServiceProtocol {
    private let client: MonadChatServiceNIOClient
    private let asyncClient: MonadChatServiceAsyncClient
    
    public var configuration: LLMConfiguration = .openAI
    public var isConfigured: Bool = true
    
    // External tool providers (e.g. MCP) - required by protocol
    public var toolProviders: [ToolProvider] = []
    
    // Service for generating text embeddings - required by protocol
    public let embeddingService: any EmbeddingService
    
    public init(channel: GRPCChannel, embeddingService: any EmbeddingService = LocalEmbeddingService()) {
        self.client = MonadChatServiceNIOClient(channel: channel)
        self.asyncClient = MonadChatServiceAsyncClient(channel: channel)
        self.embeddingService = embeddingService
    }
    
    /// Static helper to test connection without instantiating a full service or managing channel lifecycle manually in UI
    public static func testConnection(host: String, port: Int, useTLS: Bool) async throws {
        let group = NIOSingletons.posixEventLoopGroup
        let channel = try GRPCChannelPool.with(
            target: .host(host, port: port),
            transportSecurity: useTLS ? .tls : .plaintext,
            eventLoopGroup: group
        )
        
        do {
            let client = MonadChatServiceAsyncClient(channel: channel)
            var request = MonadChatRequest()
            request.userQuery = "Ping"
            request.useFastModel = true
            
            _ = try await client.sendMessage(request)
            try await channel.close().get()
        } catch {
            try? await channel.close().get()
            throw error
        }
    }
    
    public func registerToolProvider(_ provider: any ToolProvider) {
        toolProviders.append(provider)
    }

    public func loadConfiguration() async {}
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        self.configuration = config
    }
    public func clearConfiguration() async {
        isConfigured = false
    }
    public func restoreFromBackup() async throws {}
    public func exportConfiguration() async throws -> Data { return Data() }
    public func importConfiguration(from data: Data) async throws {}
    
    public func sendMessage(_ content: String) async throws -> String {
        return try await sendMessage(content, responseFormat: nil, useUtilityModel: false)
    }
    
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool) async throws -> String {
        var request = MonadChatRequest()
        request.userQuery = content
        request.useFastModel = useUtilityModel
        
        let message = try await asyncClient.sendMessage(request)
        return message.content
    }
    
    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext],
        memories: [Memory],
        databaseDirectory: [TableDirectoryEntry],
        chatHistory: [Message],
        tools: [Tool],
        systemInstructions: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>, 
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        var request = MonadChatRequest()
        request.userQuery = userQuery
        request.history = chatHistory.map { $0.toProto() }
        if let instructions = systemInstructions {
            request.systemInstructions = instructions
        }
        request.useFastModel = useFastModel
        
        let call = asyncClient.makeChatStreamCall(request)
        
        let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
            Task {
                do {
                    for try await response in call.responseStream {
                        var content: String?
                        var think: String?
                        var usage: ChatResult.CompletionUsage?
                        var model = "grpc-server"
                        
                        switch response.payload {
                        case .contentDelta(let delta):
                            content = delta
                        case .thinkDelta(let delta):
                            think = delta
                        case .metadata(let meta):
                            model = meta.model
                            usage = .init(
                                completionTokens: Int(meta.completionTokens),
                                promptTokens: Int(meta.promptTokens),
                                totalTokens: Int(meta.promptTokens + meta.completionTokens)
                            )
                        case .toolCall, .finalMessage, .none:
                            // TODO: Support other payload types
                            break
                        }
                        
                        let result = ChatStreamResult(
                            id: "grpc",
                            choices: [
                                .mock(
                                    index: 0,
                                    content: content,
                                    think: think,
                                    role: .assistant
                                )
                            ],
                            created: Date().timeIntervalSince1970,
                            model: model,
                            usage: usage
                        )
                        continuation.yield(result)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        
        return (stream, "gRPC stream", [:])
    }
    
    public func buildPrompt(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext],
        memories: [Memory],
        databaseDirectory: [TableDirectoryEntry],
        chatHistory: [Message],
        tools: [Tool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return ([], "gRPC prompt building on server", [:])
    }
    
    public func generateTags(for text: String) async throws -> [String] {
        return []
    }
    
    public func generateTitle(for messages: [Message]) async throws -> String {
        var request = MonadGenerateTitleRequest()
        request.messages = messages.map { $0.toProto() }
        let response = try await asyncClient.generateTitle(request)
        return response.title
    }
    
    public func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws -> [String : Double] {
        return [:]
    }
    
    public func fetchAvailableModels() async throws -> [String]? {
        return nil
    }
}

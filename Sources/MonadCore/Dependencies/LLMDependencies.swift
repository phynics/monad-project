import Dependencies
import Foundation
import OpenAI
import MonadPrompt

// MARK: - Dependency Keys

public enum LLMServiceKey: DependencyKey {
    public static let liveValue: any LLMServiceProtocol = UnconfiguredLLMService()
    public static let testValue: any LLMServiceProtocol = UnconfiguredLLMService()
}

public enum EmbeddingServiceKey: DependencyKey {
    public static let liveValue: any EmbeddingServiceProtocol = UnconfiguredEmbeddingService()
    public static let testValue: any EmbeddingServiceProtocol = UnconfiguredEmbeddingService()
}

// MARK: - Dependency Values

extension DependencyValues {
    public var llmService: any LLMServiceProtocol {
        get { self[LLMServiceKey.self] }
        set { self[LLMServiceKey.self] = newValue }
    }

    public var embeddingService: any EmbeddingServiceProtocol {
        get { self[EmbeddingServiceKey.self] }
        set { self[EmbeddingServiceKey.self] = newValue }
    }
}

// MARK: - Placeholder Implementations

public struct UnconfiguredLLMService: LLMServiceProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("LLMService not configured. Call 'MonadCore.configure()'.")
    }
    
    public var isConfigured: Bool { get async { false } }
    public var configuration: LLMConfiguration { 
        get async { 
            .init(
                activeProvider: .openAI, 
                providers: [:], 
                memoryContextLimit: 0, 
                documentContextLimit: 0, 
                version: 1
            ) 
        } 
    }
    
    public func getHealthStatus() async -> HealthStatus { .down }
    public func getHealthDetails() async -> [String : String]? { ["error": "Unconfigured"] }
    public func checkHealth() async -> HealthStatus { .down }

    public func loadConfiguration() async {}
    public func updateConfiguration(_ config: LLMConfiguration) async throws { fail() }
    public func clearConfiguration() async {}
    public func restoreFromBackup() async throws { fail() }
    public func exportConfiguration() async throws -> Data { fail() }
    public func importConfiguration(from data: Data) async throws { fail() }
    
    public func sendMessage(_ content: String) async throws -> String { fail() }
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool) async throws -> String { fail() }
    
    public func chatStreamWithContext(userQuery: String, contextNotes: [ContextFile], memories: [Memory], chatHistory: [Message], tools: [AnyTool], systemInstructions: String?, responseFormat: ChatQuery.ResponseFormat?, useFastModel: Bool) async -> (stream: AsyncThrowingStream<ChatStreamResult, any Error>, rawPrompt: String, structuredContext: [String : String]) {
        return (AsyncThrowingStream { _ in }, "", [:])
    }
    
    public func chatStream(messages: [ChatQuery.ChatCompletionMessageParam], tools: [ChatQuery.ChatCompletionToolParam]?, responseFormat: ChatQuery.ResponseFormat?) async -> AsyncThrowingStream<ChatStreamResult, any Error> {
        return AsyncThrowingStream { _ in }
    }
    
    public func buildPrompt(userQuery: String, contextNotes: [ContextFile], memories: [Memory], chatHistory: [Message], tools: [AnyTool], systemInstructions: String?) async -> (messages: [ChatQuery.ChatCompletionMessageParam], rawPrompt: String, structuredContext: [String : String]) {
        return ([], "", [:])
    }
    
    public func buildContext(userQuery: String, contextNotes: [ContextFile], memories: [Memory], chatHistory: [Message], tools: [AnyTool], systemInstructions: String?) async -> Prompt {
        fail()
    }
    
    public func getClient() async -> (any LLMClientProtocol)? { nil }
    public func getUtilityClient() async -> (any LLMClientProtocol)? { nil }
    
    public func generateTags(for text: String) async throws -> [String] { fail() }
    public func generateTitle(for messages: [Message]) async throws -> String { fail() }
    public func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory]) async throws -> [String : Double] { fail() }
    public func fetchAvailableModels() async throws -> [String]? { nil }
}

public struct UnconfiguredEmbeddingService: EmbeddingServiceProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("EmbeddingService not configured. Call 'MonadCore.configure()'.")
    }
    public func generateEmbedding(for text: String) async throws -> [Float] { fail() }
    public func generateEmbeddings(for texts: [String]) async throws -> [[Float]] { fail() }
}

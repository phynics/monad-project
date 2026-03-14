import Dependencies
import Foundation
import MonadPrompt
import MonadShared
import OpenAI

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

public extension DependencyValues {
    var llmService: any LLMServiceProtocol {
        get { self[LLMServiceKey.self] }
        set { self[LLMServiceKey.self] = newValue }
    }

    var embeddingService: any EmbeddingServiceProtocol {
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

    public var isConfigured: Bool {
        get async { false }
    }

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

    public func getHealthStatus() async -> HealthStatus {
        .down
    }

    public func getHealthDetails() async -> [String: String]? {
        ["error": "Unconfigured"]
    }

    public func checkHealth() async -> HealthStatus {
        .down
    }

    public func loadConfiguration() async {}
    public func updateConfiguration(_: LLMConfiguration) async throws {
        fail()
    }

    public func clearConfiguration() async {}
    public func restoreFromBackup() async throws {
        fail()
    }

    public func exportConfiguration() async throws -> Data {
        fail()
    }

    public func importConfiguration(from _: Data) async throws {
        fail()
    }

    public func sendMessage(_: String) async throws -> String {
        fail()
    }

    public func sendMessage(
        _: String,
        responseFormat _: ChatQuery.ResponseFormat?,
        useUtilityModel _: Bool
    ) async throws -> String {
        fail()
    }

    public func chatStreamWithContext(
        userQuery _: String,
        contextNotes _: [ContextFile],
        memories _: [Memory],
        chatHistory _: [Message],
        tools _: [AnyTool],
        workspaces _: [WorkspaceReference],
        primaryWorkspace _: WorkspaceReference?,
        clientName _: String?,
        systemInstructions _: String?,
        responseFormat _: ChatQuery.ResponseFormat?,
        useFastModel _: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, any Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return (AsyncThrowingStream { _ in }, "", [:])
    }

    public func chatStream(
        messages _: [ChatQuery.ChatCompletionMessageParam],
        tools _: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat _: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, any Error> {
        return AsyncThrowingStream { _ in }
    }

    public func buildPrompt(
        userQuery _: String,
        contextNotes _: [ContextFile],
        memories _: [Memory],
        chatHistory _: [Message],
        tools _: [AnyTool],
        workspaces _: [WorkspaceReference],
        primaryWorkspace _: WorkspaceReference?,
        clientName _: String?,
        systemInstructions _: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        return ([], "", [:])
    }

    public func buildContext(
        userQuery _: String,
        contextNotes _: [ContextFile],
        memories _: [Memory],
        chatHistory _: [Message],
        tools _: [AnyTool],
        workspaces _: [WorkspaceReference],
        primaryWorkspace _: WorkspaceReference?,
        clientName _: String?,
        systemInstructions _: String?,
        agentInstance _: AgentInstance?,
        timeline _: Timeline?,
        extensionSections _: [any ContextSection]
    ) async -> Prompt {
        fail()
    }

    public func getClient() async -> (any LLMClientProtocol)? {
        nil
    }

    public func getUtilityClient() async -> (any LLMClientProtocol)? {
        nil
    }

    public func generateTags(for _: String) async throws -> [String] {
        fail()
    }

    public func generateTitle(for _: [Message]) async throws -> String {
        fail()
    }

    public func evaluateRecallPerformance(transcript _: String, recalledMemories _: [Memory]) async throws -> [String: Double] {
        fail()
    }

    public func fetchAvailableModels() async throws -> [String]? {
        nil
    }
}

public struct UnconfiguredEmbeddingService: EmbeddingServiceProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("EmbeddingService not configured. Call 'MonadCore.configure()'.")
    }

    public func generateEmbedding(for _: String) async throws -> [Float] {
        fail()
    }

    public func generateEmbeddings(for _: [String]) async throws -> [[Float]] {
        fail()
    }
}

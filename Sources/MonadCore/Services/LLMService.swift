import Foundation
import OSLog
import Observation
import OpenAI

/// Protocol for LLM Clients
public protocol LLMClientProtocol: Sendable {
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error>

    func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?) async throws -> String
    
    /// Optional: Fetch available models from the service. Returns nil if not supported.
    func fetchAvailableModels() async throws -> [String]?
}

extension LLMClientProtocol {
    public func fetchAvailableModels() async throws -> [String]? {
        return nil
    }
}

// Conform OpenAIClient (Retroactive - now in same module)
extension OpenAIClient: LLMClientProtocol {}

// Conform OllamaClient
extension OllamaClient: LLMClientProtocol {}

/// Service for managing LLM interactions with configuration support
@MainActor
@Observable
public final class LLMService: LLMServiceProtocol {
    public var configuration: LLMConfiguration
    public var isConfigured: Bool

    /// External tool providers (e.g. MCP) injected from the platform targets
    public var toolProviders: [ToolProvider] = []
    
    /// Service for generating text embeddings
    public let embeddingService: any EmbeddingService

    private var client: (any LLMClientProtocol)?
    private var utilityClient: (any LLMClientProtocol)?
    private var fastClient: (any LLMClientProtocol)?
    
    private let storage: ConfigurationStorage
    public let promptBuilder: PromptBuilder
    private let logger = Logger.llm

    // MARK: - Client Accessors

    public func getClient() -> (any LLMClientProtocol)? {
        return client
    }
    
    public func getUtilityClient() -> (any LLMClientProtocol)? {
        return utilityClient
    }
    
    public func getFastClient() -> (any LLMClientProtocol)? {
        return fastClient
    }

    internal func setClients(main: (any LLMClientProtocol)?, utility: (any LLMClientProtocol)?, fast: (any LLMClientProtocol)?) {
        self.client = main
        self.utilityClient = utility
        self.fastClient = fast
    }

    // MARK: - Initialization

    public init(
        storage: ConfigurationStorage = ConfigurationStorage(),
        promptBuilder: PromptBuilder = PromptBuilder(),
        embeddingService: (any EmbeddingService)? = nil,
        client: (any LLMClientProtocol)? = nil,
        utilityClient: (any LLMClientProtocol)? = nil,
        fastClient: (any LLMClientProtocol)? = nil
    ) {
        self.storage = storage
        self.promptBuilder = promptBuilder
        self.embeddingService = embeddingService ?? LocalEmbeddingService()
        self.client = client
        self.utilityClient = utilityClient
        self.fastClient = fastClient
        
        // Load synchronously on main actor during init
        self.configuration = .openAI
        self.isConfigured = client != nil

        Task {
            await storage.migrateIfNeeded()
            if self.client == nil {
                await loadConfiguration()
            }
        }
    }

    // MARK: - Public API

    public func registerToolProvider(_ provider: ToolProvider) {
        toolProviders.append(provider)
    }

    public func loadConfiguration() async {
        let config = await storage.load()
        self.configuration = config
        self.isConfigured = config.isValid

        if config.isValid {
            logger.info("Loaded configuration. Main: \(config.modelName), Utility: \(config.utilityModel), Fast: \(config.fastModel)")
            updateClient(with: config)
        } else {
            logger.notice("LLM service not yet configured")
        }
    }

    public func restoreFromBackup() async throws {
        if let restored = try await storage.restoreFromBackup() {
            logger.info("Restored configuration from backup")
            self.configuration = restored
            self.isConfigured = restored.isValid

            if restored.isValid {
                updateClient(with: restored)
            }
        }
    }

    public func exportConfiguration() async throws -> Data {
        try await storage.exportConfiguration()
    }

    public func importConfiguration(from data: Data) async throws {
        logger.info("Importing configuration")
        try await storage.importConfiguration(from: data)
        await loadConfiguration()
    }

    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        logger.info("Updating configuration to models: \(config.modelName) / \(config.utilityModel) / \(config.fastModel)")
        try await storage.save(config)
        self.configuration = config
        self.isConfigured = config.isValid

        if config.isValid {
            updateClient(with: config)
        } else {
            setClients(main: nil, utility: nil, fast: nil)
        }
    }

    public func clearConfiguration() async {
        logger.warning("Clearing configuration")
        await storage.clear()
        self.configuration = .openAI
        self.isConfigured = false
        setClients(main: nil, utility: nil, fast: nil)
    }

    public func fetchAvailableModels() async throws -> [String]? {
        guard let client = client else {
            return nil
        }
        return try await client.fetchAvailableModels()
    }

    public func sendMessage(_ content: String) async throws -> String {
        guard let client = client else {
            throw LLMServiceError.notConfigured
        }
        return try await client.sendMessage(content, responseFormat: nil)
    }
    
    public func buildPrompt(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext] = [],
        memories: [Memory] = [],
        chatHistory: [Message],
        tools: [Tool] = [],
        systemInstructions: String? = nil
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        await promptBuilder.buildPrompt(
            systemInstructions: systemInstructions,
            contextNotes: contextNotes,
            documents: documents,
            memories: memories,
            tools: tools,
            chatHistory: chatHistory,
            userQuery: userQuery
        )
    }
}

// MARK: - Error Types

public enum LLMServiceError: LocalizedError, Equatable {
    case notConfigured
    case invalidConfiguration
    case networkError(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "LLM service is not configured. Please set up your API endpoint and key."
        case .invalidConfiguration:
            return "Invalid LLM configuration. Please check your settings."
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
import Foundation
import OSLog
import Observation
import OpenAI

/// Protocol for LLM Clients
public protocol LLMClientProtocol: Sendable {
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error>

    func sendMessage(_ content: String) async throws -> String
}

// Conform OpenAIClient (Retroactive - now in same module)
extension OpenAIClient: LLMClientProtocol {}

// Conform OllamaClient
extension OllamaClient: LLMClientProtocol {}

/// Service for managing LLM interactions with configuration support
@MainActor
@Observable
public final class LLMService {
    public var configuration: LLMConfiguration
    public var isConfigured: Bool

    /// External tool providers (e.g. MCP) injected from the platform targets
    public var toolProviders: [ToolProvider] = []

    private var client: (any LLMClientProtocol)?
    private let storage: ConfigurationStorage
    public let promptBuilder: PromptBuilder
    private let logger = Logger.llm

    /// Internal helper to get client if configured
    public func getClient() -> (any LLMClientProtocol)? {
        return client
    }

    public init(
        storage: ConfigurationStorage = ConfigurationStorage(),
        promptBuilder: PromptBuilder = PromptBuilder()
    ) {
        self.storage = storage
        self.promptBuilder = promptBuilder
        // Load synchronously on main actor during init
        self.configuration = .openAI
        self.isConfigured = false

        Task {
            // Migrate configuration if needed
            await storage.migrateIfNeeded()

            // Load configuration
            await loadConfiguration()
        }
    }

    /// Register a tool provider (e.g. MCPClient)
    public func registerToolProvider(_ provider: ToolProvider) {
        toolProviders.append(provider)
    }

    /// Load configuration from storage
    public func loadConfiguration() async {
        let config = await storage.load()
        self.configuration = config
        self.isConfigured = config.isValid

        if config.isValid {
            logger.info("Loaded configuration for model: \(config.modelName)")
            updateClient(with: config)
        } else {
            logger.notice("LLM service not yet configured")
        }
    }

    /// Restore configuration from backup
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

    /// Export configuration (without API key)
    public func exportConfiguration() async throws -> Data {
        try await storage.exportConfiguration()
    }

    /// Import configuration
    public func importConfiguration(from data: Data) async throws {
        logger.info("Importing configuration")
        try await storage.importConfiguration(from: data)
        await loadConfiguration()
    }

    /// Update configuration and persist
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        logger.info("Updating configuration to model: \(config.modelName)")
        try await storage.save(config)
        self.configuration = config
        self.isConfigured = config.isValid

        if config.isValid {
            updateClient(with: config)
        } else {
            client = nil
        }
    }

    /// Clear configuration
    public func clearConfiguration() async {
        logger.warning("Clearing configuration")
        await storage.clear()
        self.configuration = .openAI
        self.isConfigured = false
        client = nil
    }

    // MARK: - Private Methods

    /// Update LLM client with configuration
    private func updateClient(with config: LLMConfiguration) {
        logger.debug("Updating client for provider: \(config.provider.rawValue)")

        switch config.provider {
        case .ollama:
            self.client = OllamaClient(
                endpoint: config.endpoint,
                modelName: config.modelName
            )

        case .openAI, .openAICompatible:
            let components = parseEndpoint(config.endpoint)
            self.client = OpenAIClient(
                apiKey: config.apiKey,
                modelName: config.modelName,
                host: components.host,
                port: components.port,
                scheme: components.scheme
            )
        }
    }

    /// Parse endpoint URL into components (host, port, scheme)
    /// - Parameter endpoint: Full endpoint URL (e.g., "http://localhost:11434")
    /// - Returns: Tuple with host, port, and scheme
    /// - Note: Supports custom ports for local LLM servers like Ollama (11434), LM Studio (1234), etc.
    private func parseEndpoint(_ endpoint: String) -> (host: String, port: Int, scheme: String) {
        guard let url = URL(string: endpoint) else {
            logger.error("Invalid endpoint URL: \(endpoint)")
            return ("api.openai.com", 443, "https")
        }

        // For OpenAI default, ignore endpoint parsing if it's the default one being passed around
        // largely legacy behavior, can clean up later if needed.

        let host = url.host ?? "api.openai.com"
        let scheme = url.scheme ?? "https"

        // Extract port or use default based on scheme
        let port: Int
        if let urlPort = url.port {
            port = urlPort
        } else {
            port = (scheme == "https") ? 443 : 80
        }

        return (host, port, scheme)
    }

    /// Send a simple message (useful for connection testing)
    public func sendMessage(_ content: String) async throws -> String {
        guard let client = client else {
            throw LLMServiceError.notConfigured
        }

        return try await client.sendMessage(content)
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

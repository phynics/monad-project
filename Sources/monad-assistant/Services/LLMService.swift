import Foundation
import OSLog
import Observation
import OpenAI
import OpenAIClient

/// Service for managing LLM interactions with configuration support
@MainActor
@Observable
final class LLMService {
    var configuration: LLMConfiguration
    var isConfigured: Bool

    private var client: OpenAIClient?
    private let storage: ConfigurationStorage
    let promptBuilder: PromptBuilder
    private let logger = Logger.llm

    /// Internal helper to get client if configured
    func getClient() -> OpenAIClient? {
        return client
    }

    init(
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

    /// Load configuration from storage
    func loadConfiguration() async {
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
    func restoreFromBackup() async throws {
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
    func exportConfiguration() async throws -> Data {
        try await storage.exportConfiguration()
    }

    /// Import configuration
    func importConfiguration(from data: Data) async throws {
        logger.info("Importing configuration")
        try await storage.importConfiguration(from: data)
        await loadConfiguration()
    }

    /// Update configuration and persist
    func updateConfiguration(_ config: LLMConfiguration) async throws {
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
    func clearConfiguration() async {
        logger.warning("Clearing configuration")
        await storage.clear()
        self.configuration = .openAI
        self.isConfigured = false
        client = nil
    }

    // MARK: - Private Methods

    /// Update OpenAI client with configuration
    /// - Parameter config: LLM configuration including endpoint, model, and API key
    private func updateClient(with config: LLMConfiguration) {
        let components = parseEndpoint(config.endpoint)

        self.client = OpenAIClient(
            apiKey: config.apiKey,
            modelName: config.modelName,
            host: components.host,
            port: components.port,
            scheme: components.scheme
        )
        logger.debug("OpenAI client updated for \(config.endpoint)")
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
        // ...

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
    func sendMessage(_ content: String) async throws -> String {
        guard let client = client else {
            throw LLMServiceError.notConfigured
        }

        return try await client.sendMessage(content)
    }
}

// MARK: - Error Types

enum LLMServiceError: LocalizedError, Equatable {
    case notConfigured
    case invalidConfiguration
    case networkError(String)

    var errorDescription: String? {
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

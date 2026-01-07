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
    
    /// Service for generating text embeddings
    public let embeddingService: any EmbeddingService

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
        promptBuilder: PromptBuilder = PromptBuilder(),
        embeddingService: (any EmbeddingService)? = nil
    ) {
        self.storage = storage
        self.promptBuilder = promptBuilder
        self.embeddingService = embeddingService ?? LocalEmbeddingService()
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
        let cleanedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanedEndpoint), let host = url.host else {
            logger.error("Invalid endpoint URL: \(endpoint)")
            // Fallback to default if invalid, but log error. Ideally should throw if called from a throwing context.
            // For now, ensuring we don't return partial garbage.
            return ("api.openai.com", 443, "https")
        }

        let scheme = url.scheme ?? "https"
        
        // Validate scheme
        guard ["http", "https"].contains(scheme.lowercased()) else {
             logger.error("Unsupported scheme: \(scheme)")
             return ("api.openai.com", 443, "https")
        }

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

        return try await client.sendMessage(content, responseFormat: nil)
    }
    
    /// Generate tags/keywords for a given text using the LLM
    public func generateTags(for text: String) async throws -> [String] {
        guard let client = client else {
            return []
        }
        
        let prompt = """
        Extract 3-5 relevant keywords or tags from the following text.
        Return ONLY a JSON object with a key "tags" containing an array of strings.
        
        Text:
        \(text)
        """
        
        do {
            let response = try await client.sendMessage(prompt, responseFormat: .jsonObject)
            
            // Clean up response (some models might still include markdown)
            var cleanJson = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if cleanJson.hasPrefix("```json") {
                cleanJson = cleanJson.replacingOccurrences(of: "```json", with: "")
            }
            if cleanJson.hasPrefix("```") {
                cleanJson = cleanJson.replacingOccurrences(of: "```", with: "")
            }
            cleanJson = cleanJson.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            struct TagResponse: Codable {
                let tags: [String]
            }

            guard let data = cleanJson.data(using: String.Encoding.utf8),
                  let tagResponse = try? JSONDecoder().decode(TagResponse.self, from: data) else {
                logger.warning("Failed to parse tags from LLM response: \(response)")
                return []
            }
            
            return tagResponse.tags.map { $0.lowercased() }
        } catch {
            logger.error("Failed to generate tags: \(error.localizedDescription)")
            return []
        }
    }

    /// Evaluate which recalled memories were actually helpful in the conversation
    /// - Parameters:
    ///   - transcript: The conversation text
    ///   - recalledMemories: The memories that were injected as context
    /// - Returns: A dictionary mapping memory ID strings to a helpfulness score (-1.0 to 1.0)
    public func evaluateRecallPerformance(
        transcript: String,
        recalledMemories: [Memory]
    ) async throws -> [String: Double] {
        guard let client = client, !recalledMemories.isEmpty else {
            return [:]
        }

        let memoriesText = recalledMemories.map { "- ID: \($0.id.uuidString)\n  Title: \($0.title)\n  Content: \($0.content)" }.joined(separator: "\n\n")

        let prompt = """
        Analyze the following conversation transcript and the list of recalled memories that were provided to you as context.
        Determine for EACH memory if it was actually useful for answering the user's questions or providing relevant context.

        RECALLED MEMORIES:
        \(memoriesText)

        TRANSCRIPT:
        \(transcript)

        Return ONLY a JSON object where keys are memory IDs and values are helpfulness scores (numbers between -1.0 and 1.0):
        1.0: Extremely helpful, directly used to answer.
        0.5: Somewhat helpful, provided good context.
        0.0: Neutral, didn't hurt but wasn't used.
        -0.5: Irrelevant, slightly off-topic.
        -1.0: Completely irrelevant or misleading.
        """

        do {
            let response = try await client.sendMessage(prompt, responseFormat: .jsonObject)
            
            // Clean up response
            var cleanJson = response.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if cleanJson.hasPrefix("```json") {
                cleanJson = cleanJson.replacingOccurrences(of: "```json", with: "")
            }
            if cleanJson.hasPrefix("```") {
                cleanJson = cleanJson.replacingOccurrences(of: "```", with: "")
            }
            cleanJson = cleanJson.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            guard let data = cleanJson.data(using: String.Encoding.utf8),
                  let scores = try? JSONDecoder().decode([String: Double].self, from: data) else {
                logger.warning("Failed to parse recall evaluation from LLM response: \(response)")
                return [:]
            }
            
            return scores
        } catch {
            logger.error("Failed to evaluate recall: \(error.localizedDescription)")
            return [:]
        }
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

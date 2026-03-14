import Dependencies
import ErrorKit
import Foundation
import Logging
import MonadPrompt
import MonadShared
import Observation
import OpenAI

/// Protocol for LLM Clients
public protocol LLMClientProtocol: Sendable {
    func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]?,
        responseFormat: ChatQuery.ResponseFormat?
    ) async -> AsyncThrowingStream<ChatStreamResult, Error>

    func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat?) async throws
        -> String

    /// Optional: Fetch available models from the service. Returns nil if not supported.
    func fetchAvailableModels() async throws -> [String]?
}

public extension LLMClientProtocol {
    func fetchAvailableModels() async throws -> [String]? {
        return nil
    }
}

/// Conform OpenAIClient (Retroactive - now in same module)
extension OpenAIClient: LLMClientProtocol {}

/// Conform OllamaClient
extension OllamaClient: LLMClientProtocol {}

/// Service for managing LLM interactions with configuration support
public actor LLMService: LLMServiceProtocol, HealthCheckable {
    // MARK: - Constants

    private enum Constants {
        static let maxHistoryTokens = 120_000
        static let historyTokenBuffer = 4000
    }

    public private(set) var configuration: LLMConfiguration = .openAI
    public private(set) var isConfigured: Bool = false

    // MARK: - HealthCheckable

    public func getHealthStatus() async -> HealthStatus {
        return isConfigured ? .ok : .degraded
    }

    public func getHealthDetails() async -> [String: String]? {
        return [
            "model": configuration.modelName,
            "provider": configuration.endpoint.contains("openai") ? "openai" : (configuration.endpoint.contains("openrouter") ? "openrouter" : "custom"),
        ]
    }

    public func checkHealth() async -> HealthStatus {
        // Basic check: is configured
        guard isConfigured else { return .degraded }

        // Optional: Proactive check by trying to list models (if supported)
        do {
            if let client = client {
                _ = try await client.fetchAvailableModels()
                return .ok
            }
            return .degraded
        } catch {
            logger.warning("LLM health check connectivity warning: \(error)")
            // We return ok if configured even if network check fails,
            // but we could return degraded if we want to be strict.
            return .ok
        }
    }

    /// Service for generating text embeddings
    @Dependency(\.embeddingService) public var embeddingService

    private var client: (any LLMClientProtocol)?
    private var utilityClient: (any LLMClientProtocol)?
    private var fastClient: (any LLMClientProtocol)?

    private let storage: any ConfigurationServiceProtocol

    let logger = Logger.module(named: "llm")

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

    public func setClients(
        main: (any LLMClientProtocol)?, utility: (any LLMClientProtocol)?,
        fast: (any LLMClientProtocol)?
    ) {
        client = main
        utilityClient = utility
        fastClient = fast
    }

    // MARK: - Initialization

    public init(
        storage: any ConfigurationServiceProtocol,
        client: (any LLMClientProtocol)? = nil,
        utilityClient: (any LLMClientProtocol)? = nil,
        fastClient: (any LLMClientProtocol)? = nil
    ) {
        self.storage = storage
        self.client = client
        self.utilityClient = utilityClient
        self.fastClient = fastClient
        isConfigured = client != nil

        let needsLoad = client == nil

        Task { [needsLoad] in
            await storage.migrateIfNeeded()
            if needsLoad {
                await self.loadConfiguration()
            }
        }
    }

    // MARK: - Public API

    public func loadConfiguration() async {
        let config = await storage.load()
        configuration = config
        isConfigured = config.isValid

        if config.isValid {
            logger.info(
                "Loaded configuration. Main: \(config.modelName), Utility: \(config.utilityModel), Fast: \(config.fastModel)"
            )
            updateClient(with: config)
        } else {
            logger.notice("LLM service not yet configured")
        }
    }

    public func restoreFromBackup() async throws {
        if let restored = try await storage.restoreFromBackup() {
            logger.info("Restored configuration from backup")
            configuration = restored
            isConfigured = restored.isValid

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
        logger.info(
            "Updating configuration to models: \(config.modelName) / \(config.utilityModel) / \(config.fastModel)"
        )
        try await storage.save(config)
        configuration = config
        isConfigured = config.isValid

        if config.isValid {
            updateClient(with: config)
        } else {
            setClients(main: nil, utility: nil, fast: nil)
        }
    }

    public func clearConfiguration() async {
        logger.warning("Clearing configuration")
        await storage.clear()
        configuration = .openAI
        isConfigured = false
        setClients(main: nil, utility: nil, fast: nil)
    }

    public func fetchAvailableModels() async throws -> [String]? {
        guard let client = client else {
            return nil
        }
        return try await client.fetchAvailableModels()
    }

    public func sendMessage(_ content: String) async throws -> String {
        try await sendMessage(content, responseFormat: nil, useUtilityModel: false)
    }

    public func sendMessage(
        _ content: String, responseFormat: ChatQuery.ResponseFormat?, useUtilityModel: Bool
    ) async throws -> String {
        let selectedClient: (any LLMClientProtocol)?
        if useUtilityModel {
            selectedClient = utilityClient ?? client
        } else {
            selectedClient = client
        }

        guard let client = selectedClient else {
            throw LLMServiceError.notConfigured
        }
        return try await client.sendMessage(content, responseFormat: responseFormat)
    }

    public func buildContext(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String?,
        agentInstance: AgentInstance? = nil,
        timeline: Timeline? = nil
    ) async -> Prompt {
        let instructions = systemInstructions ?? DefaultInstructions.system()
        let capturedAgent = agentInstance
        let capturedTimeline = timeline

        return Prompt {
            SystemInstructions(instructions)

            // Agent identity (when an agent is attached)
            if let agent = capturedAgent {
                AgentContext(agent, timelineTitle: capturedTimeline?.title)
            }

            // Context & Memories
            ContextNotes(contextNotes)
            Memories(memories)

            // Tools
            Tools(tools)

            // Workspaces
            WorkspacesContext(
                workspaces: workspaces,
                primaryWorkspace: primaryWorkspace,
                clientName: clientName
            )

            // Current timeline identity
            if let tl = capturedTimeline {
                TimelineContext(tl)
            }

            // Conversation
            ChatHistory(optimizeHistory(chatHistory, availableTokens: Constants.maxHistoryTokens - Constants.historyTokenBuffer)) // Reserve buffer for other sections

            // User Query
            UserQuery(userQuery)
        }
    }

    func optimizeHistory(
        _ messages: [Message],
        availableTokens: Int
    ) -> [Message] {
        var result: [Message] = []
        var usedTokens = 0

        // Keep most recent messages
        for message in messages.reversed() {
            let tokens = TokenEstimator.estimate(text: message.content)
            if usedTokens + tokens <= availableTokens {
                result.insert(message, at: 0)
                usedTokens += tokens
            } else {
                // Add summary if we truncated
                if result.count < messages.count {
                    let skippedCount = messages.count - result.count
                    let summary = Message(
                        content: "[System: History truncated. \(skippedCount) earlier messages hidden. Use `view_chat_history` tool to retrieve them.]",
                        role: .system,
                        isSummary: true
                    )
                    result.insert(summary, at: 0)
                }
                break
            }
        }
        return result
    }

    public func buildPrompt(
        userQuery: String,
        contextNotes: [ContextFile],
        memories: [Memory],
        chatHistory: [Message],
        tools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        // Use the new builder locally
        let prompt = await buildContext(
            userQuery: userQuery,
            contextNotes: contextNotes,
            memories: memories,
            chatHistory: chatHistory,
            tools: tools,
            workspaces: workspaces,
            primaryWorkspace: primaryWorkspace,
            clientName: clientName,
            systemInstructions: systemInstructions
        )

        // Convert using the extension
        let messages = await prompt.toMessages()
        let raw = await prompt.render()
        let ctx = await prompt.structuredContext()

        return (messages, raw, ctx)
    }
}

// MARK: - Error Types

public enum LLMServiceError: Throwable, Equatable {
    case notConfigured
    case invalidConfiguration
    case networkError(String)

    public var userFriendlyMessage: String {
        switch self {
        case .notConfigured:
            return "LLM service is not configured. Please set up your API endpoint and key."
        case .invalidConfiguration:
            return "Invalid LLM configuration. Please check your settings."
        case let .networkError(message):
            return "Network error: \(message)"
        }
    }
}

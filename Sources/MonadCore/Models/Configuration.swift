import Foundation
import Logging

// MARK: - Configuration Model

public struct ProviderConfiguration: Codable, Sendable, Equatable {
    public var endpoint: String
    public var apiKey: String
    public var modelName: String
    public var utilityModel: String
    public var fastModel: String
    public var toolFormat: ToolCallFormat
    public var timeoutInterval: TimeInterval
    public var maxRetries: Int

    public init(
        endpoint: String,
        apiKey: String,
        modelName: String,
        utilityModel: String,
        fastModel: String,
        toolFormat: ToolCallFormat,
        timeoutInterval: TimeInterval = 60.0,
        maxRetries: Int = 3
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.utilityModel = utilityModel
        self.fastModel = fastModel
        self.toolFormat = toolFormat
        self.timeoutInterval = timeoutInterval
        self.maxRetries = maxRetries
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        modelName = try container.decode(String.self, forKey: .modelName)
        utilityModel = try container.decode(String.self, forKey: .utilityModel)
        fastModel = try container.decode(String.self, forKey: .fastModel)
        toolFormat = try container.decode(ToolCallFormat.self, forKey: .toolFormat)
        timeoutInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .timeoutInterval) ?? 60.0
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries) ?? 3
    }

    public static func defaultFor(_ provider: LLMProvider) -> ProviderConfiguration {
        switch provider {
        case .openAI:
            return ProviderConfiguration(
                endpoint: "https://api.openai.com",
                apiKey: "",
                modelName: "gpt-4o",
                utilityModel: "gpt-4o-mini",
                fastModel: "gpt-4o-mini",
                toolFormat: .openAI,
                timeoutInterval: 60.0,
                maxRetries: 3
            )
        case .openRouter:
            return ProviderConfiguration(
                endpoint: "https://openrouter.ai/api",
                apiKey: "",
                modelName: "openai/gpt-4o",
                utilityModel: "openai/gpt-4o-mini",
                fastModel: "openai/gpt-4o-mini",
                toolFormat: .openAI,
                timeoutInterval: 60.0,
                maxRetries: 3
            )
        case .ollama:
            return ProviderConfiguration(
                endpoint: "http://localhost:11434/api",
                apiKey: "",
                modelName: "llama3",
                utilityModel: "llama3",
                fastModel: "llama3",
                toolFormat: .json,
                timeoutInterval: 120.0, // Local models can be slower
                maxRetries: 3
            )
        case .openAICompatible:
            return ProviderConfiguration(
                endpoint: "http://localhost:1234/v1",
                apiKey: "",
                modelName: "model",
                utilityModel: "model",
                fastModel: "model",
                toolFormat: .openAI,
                timeoutInterval: 60.0,
                maxRetries: 3
            )
        }
    }
}

/// Configuration for LLM service
public struct LLMConfiguration: Codable, Sendable, Equatable {
    public var activeProvider: LLMProvider
    public var providers: [LLMProvider: ProviderConfiguration]

    public var mcpServers: [MCPServerConfiguration]
    public var memoryContextLimit: Int
    public var documentContextLimit: Int
    public var version: Int

    // MARK: - Computed Properties (Backwards Compatibility)

    public var endpoint: String {
        get { providers[activeProvider]?.endpoint ?? "" }
        set { providers[activeProvider]?.endpoint = newValue }
    }

    public var apiKey: String {
        get { providers[activeProvider]?.apiKey ?? "" }
        set { providers[activeProvider]?.apiKey = newValue }
    }

    public var modelName: String {
        get { providers[activeProvider]?.modelName ?? "" }
        set { providers[activeProvider]?.modelName = newValue }
    }

    public var utilityModel: String {
        get { providers[activeProvider]?.utilityModel ?? "" }
        set { providers[activeProvider]?.utilityModel = newValue }
    }

    public var fastModel: String {
        get { providers[activeProvider]?.fastModel ?? "" }
        set { providers[activeProvider]?.fastModel = newValue }
    }

    public var toolFormat: ToolCallFormat {
        get { providers[activeProvider]?.toolFormat ?? .openAI }
        set { providers[activeProvider]?.toolFormat = newValue }
    }

    public var timeoutInterval: TimeInterval {
        get { providers[activeProvider]?.timeoutInterval ?? 60.0 }
        set { providers[activeProvider]?.timeoutInterval = newValue }
    }

    public var maxRetries: Int {
        get { providers[activeProvider]?.maxRetries ?? 3 }
        set { providers[activeProvider]?.maxRetries = newValue }
    }

    public var provider: LLMProvider {
        get { activeProvider }
        set { activeProvider = newValue }
    }

    public init(
        activeProvider: LLMProvider = .openAI,
        providers: [LLMProvider: ProviderConfiguration]? = nil,
        mcpServers: [MCPServerConfiguration] = [],
        memoryContextLimit: Int = 5,
        documentContextLimit: Int = 5,
        version: Int = 5
    ) {
        self.activeProvider = activeProvider
        self.mcpServers = mcpServers
        self.memoryContextLimit = memoryContextLimit
        self.documentContextLimit = documentContextLimit
        self.version = version

        // Initialize providers with defaults if not provided
        var initialProviders: [LLMProvider: ProviderConfiguration] = [:]
        for provider in LLMProvider.allCases {
            initialProviders[provider] = ProviderConfiguration.defaultFor(provider)
        }

        // Merge provided overrides
        if let providers = providers {
            for (key, value) in providers {
                initialProviders[key] = value
            }
        }
        self.providers = initialProviders
    }

    // Convenience init for legacy support (flat structure)
    // This maps the flat arguments to the ACTIVE provider's config
    public init(
        endpoint: String = "https://api.openai.com",
        modelName: String = "gpt-4o",
        utilityModel: String = "gpt-4o-mini",
        fastModel: String = "gpt-4o-mini",
        apiKey: String = "",
        version: Int = 5,
        provider: LLMProvider = .openAI,
        toolFormat: ToolCallFormat = .openAI,
        mcpServers: [MCPServerConfiguration] = [],
        memoryContextLimit: Int = 5,
        documentContextLimit: Int = 5,
        timeoutInterval: TimeInterval = 60.0,
        maxRetries: Int = 3
    ) {
        self.activeProvider = provider
        self.mcpServers = mcpServers
        self.memoryContextLimit = memoryContextLimit
        self.documentContextLimit = documentContextLimit
        self.version = version

        // Initialize all defaults
        var initialProviders: [LLMProvider: ProviderConfiguration] = [:]
        for provider in LLMProvider.allCases {
            initialProviders[provider] = ProviderConfiguration.defaultFor(provider)
        }

        // Override the active one with passed values
        initialProviders[provider] = ProviderConfiguration(
            endpoint: endpoint,
            apiKey: apiKey,
            modelName: modelName,
            utilityModel: utilityModel,
            fastModel: fastModel,
            toolFormat: toolFormat,
            timeoutInterval: timeoutInterval,
            maxRetries: maxRetries
        )

        self.providers = initialProviders
    }

    /// Default OpenAI configuration
    public static var openAI: LLMConfiguration {
        LLMConfiguration(activeProvider: .openAI)
    }

    /// Default OpenRouter configuration
    public static var openRouter: LLMConfiguration {
        LLMConfiguration(activeProvider: .openRouter)
    }

    /// Validate configuration
    public var isValid: Bool {
        guard let config = providers[activeProvider] else { return false }

        let modelsValid =
            !config.modelName.isEmpty && !config.utilityModel.isEmpty && !config.fastModel.isEmpty
        if activeProvider == .ollama {
            return !config.endpoint.isEmpty && modelsValid && isValidEndpoint(config.endpoint)
        }
        return !config.endpoint.isEmpty && modelsValid && !config.apiKey.isEmpty
            && isValidEndpoint(config.endpoint)
    }

    /// Validate endpoint URL format
    private func isValidEndpoint(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

// MARK: - LLM Providers

public enum LLMProvider: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case openAICompatible = "OpenAI Compatible"
    case ollama = "Ollama"

    public var id: String { rawValue }
}

public enum ToolCallFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case openAI = "Native (OpenAI)"
    case json = "JSON"
    case xml = "XML"

    public var id: String { rawValue }
}

public struct MCPServerConfiguration: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var command: String
    public var arguments: [String]
    public var environment: [String: String]
    public var isEnabled: Bool = true

    public init(
        id: UUID = UUID(), name: String, command: String, arguments: [String],
        environment: [String: String], isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.environment = environment
        self.isEnabled = isEnabled
    }
}

// ConfigurationStorage moved to Services/ConfigurationStorage.swift

// MARK: - Errors

public enum ConfigurationError: LocalizedError {
    case invalidConfiguration
    case noBackupFound
    case importFailed

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid configuration: Please check all fields are properly filled."
        case .noBackupFound:
            return "No backup configuration found"
        case .importFailed:
            return "Failed to import configuration: Invalid format"
        }
    }
}

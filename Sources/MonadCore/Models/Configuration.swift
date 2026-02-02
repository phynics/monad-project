import Foundation
import OSLog

// MARK: - Configuration Model

public struct ProviderConfiguration: Codable, Sendable, Equatable {
    public var endpoint: String
    public var apiKey: String
    public var modelName: String
    public var utilityModel: String
    public var fastModel: String
    public var toolFormat: ToolCallFormat
    
    public init(
        endpoint: String,
        apiKey: String,
        modelName: String,
        utilityModel: String,
        fastModel: String,
        toolFormat: ToolCallFormat
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.utilityModel = utilityModel
        self.fastModel = fastModel
        self.toolFormat = toolFormat
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
                toolFormat: .openAI
            )
        case .openRouter:
            return ProviderConfiguration(
                endpoint: "https://openrouter.ai/api",
                apiKey: "",
                modelName: "openai/gpt-4o",
                utilityModel: "openai/gpt-4o-mini",
                fastModel: "openai/gpt-4o-mini",
                toolFormat: .openAI
            )
        case .ollama:
            return ProviderConfiguration(
                endpoint: "http://localhost:11434/api",
                apiKey: "",
                modelName: "llama3",
                utilityModel: "llama3",
                fastModel: "llama3",
                toolFormat: .json
            )
        case .openAICompatible:
            return ProviderConfiguration(
                endpoint: "http://localhost:1234/v1",
                apiKey: "",
                modelName: "model",
                utilityModel: "model",
                fastModel: "model",
                toolFormat: .openAI
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
        for p in LLMProvider.allCases {
            initialProviders[p] = ProviderConfiguration.defaultFor(p)
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
        documentContextLimit: Int = 5
    ) {
        self.activeProvider = provider
        self.mcpServers = mcpServers
        self.memoryContextLimit = memoryContextLimit
        self.documentContextLimit = documentContextLimit
        self.version = version
        
        // Initialize all defaults
        var initialProviders: [LLMProvider: ProviderConfiguration] = [:]
        for p in LLMProvider.allCases {
            initialProviders[p] = ProviderConfiguration.defaultFor(p)
        }
        
        // Override the active one with passed values
        initialProviders[provider] = ProviderConfiguration(
            endpoint: endpoint,
            apiKey: apiKey,
            modelName: modelName,
            utilityModel: utilityModel,
            fastModel: fastModel,
            toolFormat: toolFormat
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
        
        let modelsValid = !config.modelName.isEmpty && !config.utilityModel.isEmpty && !config.fastModel.isEmpty
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

// MARK: - Configuration Storage

/// Thread-safe configuration storage using AppStorage (UserDefaults)
public actor ConfigurationStorage {
    private let userDefaults: UserDefaults
    private let configKey = "llm_configuration_v2" // Bumped key
    private let backupKey = "llm_configuration_backup_v2"
    private let oldConfigKey = "llm_configuration_v1"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Load

    /// Load configuration from storage
    public func load() -> LLMConfiguration {
        // Try loading new format
        if let data = userDefaults.data(forKey: configKey),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            return config
        }
        
        // Fallback: Try loading old format (v1) and migrate on the fly if strictly necessary
        // But migrateIfNeeded is called on startup.
        // If nothing found, return default.
        return .openAI
    }

    // MARK: - Save

    /// Save configuration to storage
    public func save(_ configuration: LLMConfiguration) throws {
        // Validate before saving
        guard configuration.isValid else {
            throw ConfigurationError.invalidConfiguration
        }

        // Create backup before saving
        try? createBackup(configuration)

        // Save all settings (including API key) to UserDefaults
        let data = try JSONEncoder().encode(configuration)
        userDefaults.set(data, forKey: configKey)

        // Ensure changes are persisted
        userDefaults.synchronize()
    }

    // MARK: - Clear

    /// Clear stored configuration
    public func clear() {
        userDefaults.removeObject(forKey: configKey)
        userDefaults.removeObject(forKey: backupKey)
        userDefaults.synchronize()
    }

    // MARK: - Backup & Restore

    /// Create backup of current configuration
    private func createBackup(_ configuration: LLMConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        userDefaults.set(data, forKey: backupKey)
    }

    /// Load configuration from backup
    private func loadBackup() -> LLMConfiguration? {
        guard let data = userDefaults.data(forKey: backupKey),
            let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data)
        else {
            return nil
        }
        return config
    }

    /// Restore from backup
    public func restoreFromBackup() throws -> LLMConfiguration? {
        guard let backup = loadBackup() else {
            throw ConfigurationError.noBackupFound
        }

        try save(backup)
        return backup
    }

    // MARK: - Export & Import

    /// Export configuration (without API key for security)
    public func exportConfiguration() throws -> Data {
        var config = load()
        // Clear API keys for all providers
        for key in config.providers.keys {
            config.providers[key]?.apiKey = ""
        }
        return try JSONEncoder().encode(config)
    }

    /// Import configuration from data
    public func importConfiguration(from data: Data) throws {
        let config = try JSONDecoder().decode(LLMConfiguration.self, from: data)
        let currentConfig = load()

        // Validate imported config and restore API keys from current config if missing
        var validatedConfig = config
        
        for (provider, _) in validatedConfig.providers {
            if validatedConfig.providers[provider]?.apiKey.isEmpty ?? true {
                validatedConfig.providers[provider]?.apiKey = currentConfig.providers[provider]?.apiKey ?? ""
            }
        }

        try save(validatedConfig)
    }

    // MARK: - Migration

    /// Migrate from old configuration format if needed
    public func migrateIfNeeded() async {
        // V1 -> V2 Migration
        // Check if we have data in the old key AND no data in the new key
        if userDefaults.data(forKey: configKey) == nil,
           let oldData = userDefaults.data(forKey: oldConfigKey) {
            
            // Define a temporary struct matching V1 structure to decode
            struct LegacyLLMConfigurationV1: Codable {
                var endpoint: String
                var modelName: String
                var utilityModel: String
                var fastModel: String
                var apiKey: String
                var version: Int
                var provider: LLMProvider
                var toolFormat: ToolCallFormat
                var mcpServers: [MCPServerConfiguration]
                var memoryContextLimit: Int
                var documentContextLimit: Int
            }
            
            if let oldConfig = try? JSONDecoder().decode(LegacyLLMConfigurationV1.self, from: oldData) {
                Logger.llm.info("Migrating configuration from V1 to V2...")
                
                // Initialize defaults
                var newProviders: [LLMProvider: ProviderConfiguration] = [:]
                for p in LLMProvider.allCases {
                    newProviders[p] = ProviderConfiguration.defaultFor(p)
                }
                
                // Update the active provider with legacy values
                newProviders[oldConfig.provider] = ProviderConfiguration(
                    endpoint: oldConfig.endpoint,
                    apiKey: oldConfig.apiKey,
                    modelName: oldConfig.modelName,
                    utilityModel: oldConfig.utilityModel,
                    fastModel: oldConfig.fastModel,
                    toolFormat: oldConfig.toolFormat
                )
                
                let newConfig = LLMConfiguration(
                    activeProvider: oldConfig.provider,
                    providers: newProviders,
                    mcpServers: oldConfig.mcpServers,
                    memoryContextLimit: oldConfig.memoryContextLimit,
                    documentContextLimit: oldConfig.documentContextLimit,
                    version: 5
                )
                
                try? save(newConfig)
                // Optional: remove old key
                // userDefaults.removeObject(forKey: oldConfigKey) 
            }
        }
    }
}

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

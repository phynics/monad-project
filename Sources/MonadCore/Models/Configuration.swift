import Foundation

// MARK: - Configuration Model

/// Configuration for LLM service
public struct LLMConfiguration: Codable, Sendable, Equatable {
    public var endpoint: String
    public var modelName: String
    public var utilityModel: String
    public var fastModel: String
    public var apiKey: String
    public var version: Int
    public var provider: LLMProvider
    public var toolFormat: ToolCallFormat
    public var mcpServers: [MCPServerConfiguration]
    public var memoryContextLimit: Int
    public var documentContextLimit: Int

    public init(
        endpoint: String = "https://api.openai.com",
        modelName: String = "gpt-4o",
        utilityModel: String = "gpt-4o-mini",
        fastModel: String = "gpt-4o-mini",
        apiKey: String = "",
        version: Int = 4,
        provider: LLMProvider = .openAI,
        toolFormat: ToolCallFormat = .openAI,
        mcpServers: [MCPServerConfiguration] = [],
        memoryContextLimit: Int = 10,
        documentContextLimit: Int = 5
    ) {
        self.endpoint = endpoint
        self.modelName = modelName
        self.utilityModel = utilityModel
        self.fastModel = fastModel
        self.apiKey = apiKey
        self.version = version
        self.provider = provider
        self.toolFormat = toolFormat
        self.mcpServers = mcpServers
        self.memoryContextLimit = memoryContextLimit
        self.documentContextLimit = documentContextLimit
    }

    /// Default OpenAI configuration
    public static var openAI: LLMConfiguration {
        LLMConfiguration(
            endpoint: "https://api.openai.com",
            modelName: "gpt-4o",
            utilityModel: "gpt-4o-mini",
            fastModel: "gpt-4o-mini",
            apiKey: "",
            provider: .openAI,
            toolFormat: .openAI,
            memoryContextLimit: 10,
            documentContextLimit: 5
        )
    }

    /// Validate configuration
    public var isValid: Bool {
        let modelsValid = !modelName.isEmpty && !utilityModel.isEmpty && !fastModel.isEmpty
        if provider == .ollama {
            return !endpoint.isEmpty && modelsValid && isValidEndpoint(endpoint)
        }
        return !endpoint.isEmpty && modelsValid && !apiKey.isEmpty
            && isValidEndpoint(endpoint)
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
    private let configKey = "llm_configuration_v1"
    private let backupKey = "llm_configuration_backup"

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Load

    /// Load configuration from storage
    public func load() -> LLMConfiguration {
        // Load settings from UserDefaults
        guard let data = userDefaults.data(forKey: configKey),
            let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data)
        else {
            return .openAI
        }

        return config
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
        config.apiKey = ""  // Don't export API key
        return try JSONEncoder().encode(config)
    }

    /// Import configuration from data
    public func importConfiguration(from data: Data) throws {
        let config = try JSONDecoder().decode(LLMConfiguration.self, from: data)

        // Validate imported config
        var validatedConfig = config
        if validatedConfig.apiKey.isEmpty {
            // Keep existing API key if import doesn't have one
            validatedConfig.apiKey = load().apiKey
        }

        try save(validatedConfig)
    }

    // MARK: - Migration

    /// Migrate from old configuration format if needed
    public func migrateIfNeeded() async {
        // Check for old format (v0 - no version field)
        let oldKey = "llm_configuration"
        if let oldData = userDefaults.data(forKey: oldKey),
            let oldConfig = try? JSONDecoder().decode(LLMConfiguration.self, from: oldData)
        {
            // Migrate to new format
            do {
                var migratedConfig = oldConfig
                // V1 -> V2
                migratedConfig.version = 2
                migratedConfig.provider = .openAI
                migratedConfig.toolFormat = .openAI
                migratedConfig.mcpServers = []

                try save(migratedConfig)

                // Remove old key
                userDefaults.removeObject(forKey: oldKey)
                print("Configuration migrated successfully")
            } catch {
                print("Failed to migrate configuration: \(error)")
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

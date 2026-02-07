import Foundation
import Logging

// MARK: - Configuration Storage

/// Thread-safe configuration storage using AppStorage (UserDefaults)
public actor ConfigurationStorage {
    private let userDefaults: UserDefaults
    private let configKey = "llm_configuration_v2"  // Bumped key
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
            let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data)
        {
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
                validatedConfig.providers[provider]?.apiKey =
                    currentConfig.providers[provider]?.apiKey ?? ""
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
            let oldData = userDefaults.data(forKey: oldConfigKey)
        {

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

            if let oldConfig = try? JSONDecoder().decode(
                LegacyLLMConfigurationV1.self, from: oldData)
            {
                Logger.llm.info("Migrating configuration from V1 to V2...")

                // Initialize defaults
                var newProviders: [LLMProvider: ProviderConfiguration] = [:]
                for provider in LLMProvider.allCases {
                    newProviders[provider] = ProviderConfiguration.defaultFor(provider)
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

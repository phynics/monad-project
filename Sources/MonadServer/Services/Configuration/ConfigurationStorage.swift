import MonadCore
import MonadShared
import Foundation
import Logging

// MARK: - Configuration Storage

/// Thread-safe configuration storage using a local JSON file
public actor ConfigurationStorage: ConfigurationServiceProtocol {
    private let configURL: URL
    private let backupURL: URL
    private let userDefaults: UserDefaults // Keep for migration only
    private let logger = Logger.server

    public init(configURL: URL, userDefaults: UserDefaults = .standard) {
        self.configURL = configURL
        self.backupURL = configURL.deletingPathExtension().appendingPathExtension("bak")
        self.userDefaults = userDefaults
    }

    // MARK: - Load

    /// Load configuration from storage
    public func load() -> LLMConfiguration {
        var config: LLMConfiguration

        // 1. Try loading from file
        if let data = try? Data(contentsOf: configURL) {
            do {
                config = try JSONDecoder().decode(LLMConfiguration.self, from: data)
            } catch {
                logger.error("Failed to decode configuration from \(configURL.path): \(error)")

                // 1.1 Try loading from backup
                if let backup = loadBackup() {
                    logger.info("Restored configuration from backup.")
                    config = backup
                } else {
                    logger.warning("No valid backup found. Falling back to default.")
                    config = .openAI
                }
            }
        } else {
            // 2. Fallback to default
            config = .openAI
        }

        // 3. Apply Environment Variable Overrides
        applyEnvironmentOverrides(to: &config)

        return config
    }

    private func applyEnvironmentOverrides(to config: inout LLMConfiguration) {
        let env = ProcessInfo.processInfo.environment

        // MONAD_API_KEY can override the active provider's key
        if let envKey = env["MONAD_API_KEY"], !envKey.isEmpty {
            config.providers[config.activeProvider]?.apiKey = envKey
        }

        // Provider-specific overrides (e.g. MONAD_OPENAI_API_KEY)
        for provider in LLMProvider.allCases {
            let safeName = provider.rawValue.replacingOccurrences(of: " ", with: "_").uppercased()
            let envVarName = "MONAD_\(safeName)_API_KEY"
            if let envKey = env[envVarName], !envKey.isEmpty {
                config.providers[provider]?.apiKey = envKey
            }
        }
    }

    // MARK: - Save

    /// Save configuration to storage
    public func save(_ configuration: LLMConfiguration) throws {
        // Ensure parent directory exists
        let dir = configURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Create backup before saving
        try? createBackup(configuration)

        // Save all settings (including API key) to file
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: configURL, options: .atomic)
    }

    // MARK: - Clear

    /// Clear stored configuration
    public func clear() {
        try? FileManager.default.removeItem(at: configURL)
        try? FileManager.default.removeItem(at: backupURL)
    }

    // MARK: - Backup & Restore

    /// Create backup of current configuration
    private func createBackup(_ configuration: LLMConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        try data.write(to: backupURL, options: .atomic)
    }

    /// Load configuration from backup
    private func loadBackup() -> LLMConfiguration? {
        guard let data = try? Data(contentsOf: backupURL),
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
        let configKey = "llm_configuration_v2"
        let oldConfigKey = "llm_configuration_v1"

        // 1. Check if we already have file-based config
        if FileManager.default.fileExists(atPath: configURL.path) {
            return
        }

        // 2. Try migrating from UserDefaults V2
        if let data = userDefaults.data(forKey: configKey),
           let config = try? JSONDecoder().decode(LLMConfiguration.self, from: data) {
            logger.info("Migrating configuration from UserDefaults V2 to file...")
            try? save(config)
            return
        }

        // 3. V1 -> V2 Migration from UserDefaults
        if let oldData = userDefaults.data(forKey: oldConfigKey) {
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
                LegacyLLMConfigurationV1.self, from: oldData) {
                logger.info("Migrating configuration from V1 to file...")

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
            }
        }
    }
}

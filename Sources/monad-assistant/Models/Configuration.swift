import Foundation

// MARK: - Configuration Model

/// Configuration for LLM service
struct LLMConfiguration: Codable, Sendable, Equatable {
    var endpoint: String
    var modelName: String
    var apiKey: String
    var version: Int

    init(
        endpoint: String = "https://api.openai.com",
        modelName: String = "gpt-4o",
        apiKey: String = "",
        version: Int = 1
    ) {
        self.endpoint = endpoint
        self.modelName = modelName
        self.apiKey = apiKey
        self.version = version
    }

    /// Default OpenAI configuration
    static var openAI: LLMConfiguration {
        LLMConfiguration(
            endpoint: "https://api.openai.com",
            modelName: "gpt-4o",
            apiKey: ""
        )
    }

    /// Validate configuration
    var isValid: Bool {
        !endpoint.isEmpty && !modelName.isEmpty && !apiKey.isEmpty && isValidEndpoint(endpoint)
    }

    /// Validate endpoint URL format
    private func isValidEndpoint(_ endpoint: String) -> Bool {
        guard let url = URL(string: endpoint) else { return false }
        return url.scheme == "http" || url.scheme == "https"
    }
}

// MARK: - Configuration Storage

/// Thread-safe configuration storage using AppStorage (UserDefaults)
actor ConfigurationStorage {
    private let userDefaults: UserDefaults
    private let configKey = "llm_configuration_v1"
    private let backupKey = "llm_configuration_backup"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Load

    /// Load configuration from storage
    func load() -> LLMConfiguration {
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
    func save(_ configuration: LLMConfiguration) throws {
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
    func clear() {
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
    func restoreFromBackup() throws -> LLMConfiguration? {
        guard let backup = loadBackup() else {
            throw ConfigurationError.noBackupFound
        }

        try save(backup)
        return backup
    }

    // MARK: - Export & Import

    /// Export configuration (without API key for security)
    func exportConfiguration() throws -> Data {
        var config = load()
        config.apiKey = ""  // Don't export API key
        return try JSONEncoder().encode(config)
    }

    /// Import configuration from data
    func importConfiguration(from data: Data) throws {
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
    func migrateIfNeeded() async {
        // Check for old format (v0 - no version field)
        let oldKey = "llm_configuration"
        if let oldData = userDefaults.data(forKey: oldKey),
            let oldConfig = try? JSONDecoder().decode(LLMConfiguration.self, from: oldData)
        {

            // Migrate to new format
            do {
                var migratedConfig = oldConfig
                migratedConfig.version = 1
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

enum ConfigurationError: LocalizedError {
    case invalidConfiguration
    case noBackupFound
    case importFailed

    var errorDescription: String? {
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

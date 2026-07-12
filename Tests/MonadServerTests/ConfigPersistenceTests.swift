import PKShared
import MonadShared
import PositronicKit
import Foundation
@testable import MonadServerCore
import Testing

@Suite struct ConfigPersistenceTests {
    @Test("Legacy V1 JSON/XML tool formats migrate to the supported native format")
    func legacyToolFormatMigrationIsLenient() async throws {
        let suiteName = "config_legacy_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "config_legacy_\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let legacy: [String: Any] = [
            "endpoint": "https://openrouter.ai/api/v1",
            "modelName": "test-model",
            "utilityModel": "utility-model",
            "fastModel": "fast-model",
            "apiKey": "legacy-key",
            "version": 1,
            "provider": "OpenRouter",
            "toolFormat": "JSON",
            "memoryContextLimit": 10,
            "documentContextLimit": 10,
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: legacy),
            forKey: "llm_configuration_v1"
        )

        let storage = ConfigurationStorage(configURL: tempURL, userDefaults: defaults)
        await storage.migrateIfNeeded()
        let migrated = await storage.load()

        #expect(migrated.providers[.openRouter]?.toolFormat == .openAI)
        #expect(migrated.providers[.openRouter]?.apiKey == "legacy-key")
    }

    @Test("Configuration should be persisted across service instances")
    func persistence() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "config_test_\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // 1. First instance - Update config
        do {
            let storage = ConfigurationStorage(configURL: tempURL)
            let service = LLMService(storage: storage)
            await service.loadConfiguration()

            var config = await service.configuration
            config.activeProvider = .ollama
            config.providers[.ollama]?.modelName = "persistence-test-model"
            config.providers[.ollama]?.endpoint = "http://localhost:11434/api"

            try await service.updateConfiguration(config)

            // Verify immediate state
            let current = await service.configuration
            #expect(current.activeProvider == .ollama)
            #expect(current.providers[.ollama]?.modelName == "persistence-test-model")
        }

        // 2. Second instance - Should load saved config
        do {
            let storage = ConfigurationStorage(configURL: tempURL)
            let service = LLMService(storage: storage)
            await service.loadConfiguration()

            let loaded = await service.configuration
            #expect(loaded.activeProvider == .ollama)
            #expect(loaded.providers[.ollama]?.modelName == "persistence-test-model")
        }
    }
}

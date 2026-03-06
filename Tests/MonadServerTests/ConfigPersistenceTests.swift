import MonadShared
import MonadCore
import Foundation
@testable import MonadServer
import Testing

@Suite struct ConfigPersistenceTests {
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

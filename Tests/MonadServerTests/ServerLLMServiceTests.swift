import Testing
import Foundation
@testable import MonadServerCore
import MonadCore

@Suite struct ServerLLMServiceTests {
    
    @Test("Test ServerLLMService Initialization and Config Load")
    func testInitialization() async throws {
        let defaults = UserDefaults(suiteName: "TestServerLLMService")!
        defaults.removePersistentDomain(forName: "TestServerLLMService")
        
        let storage = ConfigurationStorage(userDefaults: defaults)
        let service = ServerLLMService(storage: storage)
        
        await service.loadConfiguration()
        
        let client = await service.getClient()
        #expect(client == nil, "Client should be nil initially (no API Key)")
        
        // Test updating configuration
        var config = await service.getConfiguration()
        config.activeProvider = .ollama
        config.providers[.ollama]?.modelName = "test-model"
        // Ollama doesn't need API Key, just endpoint
        config.providers[.ollama]?.endpoint = "http://localhost:11434/api"
        
        try await service.updateConfiguration(config)
        
        let newConfig = await service.getConfiguration()
        #expect(newConfig.activeProvider == .ollama)
        
        let newClient = await service.getClient()
        #expect(newClient != nil, "Client should be initialized after valid config")
    }
}

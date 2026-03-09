import Testing
@testable import MonadCore
@testable import MonadShared
import Foundation

@Suite final class LLMConfigurationModelsTests {
    
    // MARK: - Test Helpers
    
    private func assertCodable<T: Codable & Equatable>(_ value: T) throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        #expect(value == decoded)
    }
    
    @Test

    
    func testLLMConfigurationCodable() throws {
        let config = LLMConfiguration(
            activeProvider: .openRouter,
            providers: [
                .openRouter: ProviderConfiguration(
                    endpoint: "https://openrouter.ai/api/v1",
                    apiKey: "sk-or-v1-test",
                    modelName: "anthropic/claude-3-5-sonnet",
                    utilityModel: "gpt-4o-mini",
                    fastModel: "gpt-4o-mini",
                    toolFormat: .openAI
                )
            ]
        )
        try assertCodable(config)
    }
    
    @Test

    
    func testLLMConfigurationDefault() {
        let config = LLMConfiguration.default
        #expect(config.activeProvider == .openAI)
    }
    
    // MARK: - LLMProvider
    
    @Test

    
    func testLLMProviderCodableAndStr() throws {
        let p1 = LLMProvider.openAI
        try assertCodable(p1)
        #expect(p1.rawValue == "OpenAI")
        
        let p2 = LLMProvider.openRouter
        #expect(p2.rawValue == "OpenRouter")
        
        let p3 = LLMProvider.ollama
        #expect(p3.rawValue == "Ollama")
    }
    
    // MARK: - ProviderConfiguration
    
    @Test

    
    func testProviderConfigurationCodable() throws {
        let config = ProviderConfiguration(
            endpoint: "http://localhost:11434/api",
            apiKey: "",
            modelName: "llama3",
            utilityModel: "llama3",
            fastModel: "llama3",
            toolFormat: .json
        )
        try assertCodable(config)
        #expect(config.toolFormat == .json)
    }
    
    // MARK: - ToolCallFormat
    
    @Test

    
    func testToolCallFormatCodable() throws {
        let f1 = ToolCallFormat.openAI
        try assertCodable(f1)
        
        let f2 = ToolCallFormat.json
        try assertCodable(f2)
        
        let f3 = ToolCallFormat.xml
        try assertCodable(f3)
    }
}

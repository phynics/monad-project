import Foundation
import MonadCore
import Testing

@Suite struct LLMConfigurationTests {
    
    @Test("Default configuration validity")
    func defaultConfiguration() {
        let config = LLMConfiguration.openAI
        #expect(!config.isValid) // Invalid because API key is empty
        #expect(config.provider == .openAI)
    }
    
    @Test("Valid OpenAI configuration")
    func validOpenAI() {
        let config = LLMConfiguration(
            endpoint: "https://api.openai.com",
            modelName: "gpt-4",
            apiKey: "sk-12345",
            provider: .openAI
        )
        #expect(config.isValid)
    }
    
    @Test("Valid Ollama configuration (No API Key)")
    func validOllama() {
        let config = LLMConfiguration(
            endpoint: "http://localhost:11434",
            modelName: "llama3",
            apiKey: "",
            provider: .ollama
        )
        #expect(config.isValid)
    }
    
    @Test("Invalid Endpoint")
    func invalidEndpoint() {
        let config = LLMConfiguration(
            endpoint: "not-a-url",
            modelName: "gpt-4",
            apiKey: "sk-123",
            provider: .openAI
        )
        #expect(!config.isValid)
    }
    
    @Test("Missing Model Name")
    func missingModel() {
        let config = LLMConfiguration(
            endpoint: "https://api.openai.com",
            modelName: "",
            apiKey: "sk-123",
            provider: .openAI
        )
        #expect(!config.isValid)
    }
}

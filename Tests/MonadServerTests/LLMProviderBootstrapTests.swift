import PKOllamaProvider
import PKOpenAIProvider
import PKOpenRouterProvider
import PKShared
@testable import MonadServerCore
import Testing

@Suite struct LLMProviderBootstrapTests {
    @Test("makeClientFactory builds clients for bundled providers")
    func makeClientFactory_buildsClients() {
        let factory = LLMProviderBootstrap.makeClientFactory()

        let openAIConfig = LLMConfiguration(activeProvider: .openAI)
        let openAIClients = factory?(openAIConfig)
        #expect(openAIClients?.main != nil)

        let openRouterConfig = LLMConfiguration(activeProvider: .openRouter)
        let openRouterClients = factory?(openRouterConfig)
        #expect(openRouterClients?.main != nil)

        let ollamaConfig = LLMConfiguration(activeProvider: .ollama)
        let ollamaClients = factory?(ollamaConfig)
        #expect(ollamaClients?.main != nil)

        let anthropicConfig = LLMConfiguration(activeProvider: .anthropic)
        let anthropicClients = factory?(anthropicConfig)
        #expect(anthropicClients?.main != nil)
    }
}

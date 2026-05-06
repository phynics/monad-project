import PKShared
@testable import MonadServer
import Testing

@Suite struct LLMProviderBootstrapTests {
    @Test("registerBuiltIns exposes factories for bundled providers")
    func registerBuiltIns_exposesFactories() {
        LLMProviderBootstrap.registerBuiltIns()

        #expect(ExternalLLMProviderRegistry.factory(for: .openAI) != nil)
        #expect(ExternalLLMProviderRegistry.factory(for: .openAICompatible) != nil)
        #expect(ExternalLLMProviderRegistry.factory(for: .openRouter) != nil)
        #expect(ExternalLLMProviderRegistry.factory(for: .ollama) != nil)
    }
}

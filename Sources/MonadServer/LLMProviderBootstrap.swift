import PKOllamaProvider
import PKOpenAIProvider
import PKOpenRouterProvider

enum LLMProviderBootstrap {
    static func registerBuiltIns() {
        PKOpenAIProvider.register()
        PKOpenRouterProvider.register()
        PKOllamaProvider.register()
    }
}

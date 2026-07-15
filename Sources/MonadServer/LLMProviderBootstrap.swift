import PKAnthropicProvider
import PKOllamaProvider
import PKOpenAIProvider
import PKOpenRouterProvider
import PKShared

enum LLMProviderBootstrap {
    static func makeClientFactory() -> (@Sendable (LLMConfiguration) -> (
        main: (any LLMClientProtocol)?, utility: (any LLMClientProtocol)?,
        fast: (any LLMClientProtocol)?
    ))? {
        { config in
            let clients: (main: (any LLMClientProtocol)?, utility: (any LLMClientProtocol)?,
                fast: (any LLMClientProtocol)?)
            switch config.activeProvider {
            case .openAI:
                clients = (main: PKOpenAIProvider.makeClient(configuration: config),
                           utility: nil, fast: nil)
            case .openRouter:
                clients = (main: PKOpenRouterProvider.makeClient(configuration: config),
                           utility: nil, fast: nil)
            case .ollama:
                clients = (main: PKOllamaProvider.makeClient(configuration: config),
                           utility: nil, fast: nil)
            case .anthropic:
                clients = (main: PKAnthropicProvider.makeClient(configuration: config),
                           utility: nil, fast: nil)
            case .openAICompatible:
                clients = (main: PKOpenAIProvider.makeClient(configuration: config),
                           utility: nil, fast: nil)
            }
            return clients
        }
    }
}

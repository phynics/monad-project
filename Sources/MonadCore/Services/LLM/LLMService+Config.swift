import Foundation
import Logging
import MonadShared
import OpenAI

extension LLMService {
    // MARK: - Internal Configuration Helpers

    /// Update LLM client with configuration
    func updateClient(with config: LLMConfiguration) {
        Logger.module(named: "llm").debug("Updating clients for provider: \(config.provider.rawValue)")

        let components = parseEndpoint(config.endpoint)
        let timeout = config.timeoutInterval
        let retries = config.maxRetries

        switch config.provider {
        case .ollama:
            setClients(
                main: makeOllamaClient(config: config, timeout: timeout, retries: retries),
                utility: makeOllamaClient(
                    config: config, timeout: timeout, retries: retries, model: config.utilityModel
                ),
                fast: makeOllamaClient(
                    config: config, timeout: timeout, retries: retries, model: config.fastModel
                )
            )

        case .openRouter:
            setClients(
                main: makeOpenRouterClient(config: config, components: components, timeout: timeout, retries: retries),
                utility: makeOpenRouterClient(
                    config: config, components: components, timeout: timeout, retries: retries,
                    model: config.utilityModel
                ),
                fast: makeOpenRouterClient(
                    config: config, components: components, timeout: timeout, retries: retries,
                    model: config.fastModel
                )
            )

        case .openAI, .openAICompatible:
            setClients(
                main: makeOpenAIClient(config: config, components: components, timeout: timeout, retries: retries),
                utility: makeOpenAIClient(
                    config: config, components: components, timeout: timeout, retries: retries,
                    model: config.utilityModel
                ),
                fast: makeOpenAIClient(
                    config: config, components: components, timeout: timeout, retries: retries,
                    model: config.fastModel
                )
            )
        }
    }

    /// Parse an endpoint URL into its host, port, and scheme components.
    func parseEndpoint(_ endpoint: String) -> EndpointComponents {
        let cleanedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanedEndpoint), let host = url.host else {
            Logger.module(named: "llm").error("Invalid endpoint URL: \(endpoint)")
            return EndpointComponents(host: "api.openai.com", port: 443, scheme: "https")
        }

        let scheme = url.scheme ?? "https"
        guard ["http", "https"].contains(scheme.lowercased()) else {
            Logger.module(named: "llm").error("Unsupported scheme: \(scheme)")
            return EndpointComponents(host: "api.openai.com", port: 443, scheme: "https")
        }

        let port: Int
        if let urlPort = url.port {
            port = urlPort
        } else {
            port = (scheme == "https") ? 443 : 80
        }

        return EndpointComponents(host: host, port: port, scheme: scheme)
    }

    // MARK: - Client Factories

    private func makeOllamaClient(
        config: LLMConfiguration,
        timeout: TimeInterval,
        retries: Int,
        model: String? = nil
    ) -> OllamaClient {
        OllamaClient(
            endpoint: config.endpoint,
            modelName: model ?? config.modelName,
            timeoutInterval: timeout,
            maxRetries: retries
        )
    }

    private func makeOpenRouterClient(
        config: LLMConfiguration,
        components: EndpointComponents,
        timeout: TimeInterval,
        retries: Int,
        model: String? = nil
    ) -> OpenRouterClient {
        OpenRouterClient(
            apiKey: config.apiKey,
            modelName: model ?? config.modelName,
            host: components.host,
            port: components.port,
            scheme: components.scheme,
            timeoutInterval: timeout,
            maxRetries: retries
        )
    }

    private func makeOpenAIClient(
        config: LLMConfiguration,
        components: EndpointComponents,
        timeout: TimeInterval,
        retries: Int,
        model: String? = nil
    ) -> OpenAIClient {
        OpenAIClient(
            apiKey: config.apiKey,
            modelName: model ?? config.modelName,
            host: components.host,
            port: components.port,
            scheme: components.scheme,
            timeoutInterval: timeout,
            maxRetries: retries
        )
    }
}

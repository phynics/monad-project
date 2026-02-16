import MonadShared
import Foundation
import Logging
import OpenAI

extension LLMService {
    // MARK: - Internal Configuration Helpers

    /// Update LLM client with configuration
    internal func updateClient(with config: LLMConfiguration) {
        Logger.llm.debug("Updating clients for provider: \(config.provider.rawValue)")

        let components = parseEndpoint(config.endpoint)
        let timeout = config.timeoutInterval
        let retries = config.maxRetries
        
        switch config.provider {
        case .ollama:
            self.setClients(
                main: OllamaClient(
                    endpoint: config.endpoint,
                    modelName: config.modelName,
                    timeoutInterval: timeout,
                    maxRetries: retries
                ),
                utility: OllamaClient(
                    endpoint: config.endpoint,
                    modelName: config.utilityModel,
                    timeoutInterval: timeout,
                    maxRetries: retries
                ),
                fast: OllamaClient(
                    endpoint: config.endpoint,
                    modelName: config.fastModel,
                    timeoutInterval: timeout,
                    maxRetries: retries
                )
            )

        case .openRouter:
            self.setClients(
                main: OpenRouterClient(
                    apiKey: config.apiKey,
                    modelName: config.modelName,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme,
                    timeoutInterval: timeout,
                    maxRetries: retries
                ),
                utility: OpenRouterClient(
                    apiKey: config.apiKey,
                    modelName: config.utilityModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme,
                    timeoutInterval: timeout,
                    maxRetries: retries
                ),
                fast: OpenRouterClient(
                    apiKey: config.apiKey,
                    modelName: config.fastModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme,
                    timeoutInterval: timeout,
                    maxRetries: retries
                )
            )

        case .openAI, .openAICompatible:
            self.setClients(
                main: OpenAIClient(
                    apiKey: config.apiKey,
                    modelName: config.modelName,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme,
                    timeoutInterval: timeout,
                    maxRetries: retries
                ),
                utility: OpenAIClient(
                    apiKey: config.apiKey,
                    modelName: config.utilityModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme,
                    timeoutInterval: timeout,
                    maxRetries: retries
                ),
                fast: OpenAIClient(
                    apiKey: config.apiKey,
                    modelName: config.fastModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme,
                    timeoutInterval: timeout,
                    maxRetries: retries
                )
            )
        }
    }

    /// - Parameter endpoint: Full endpoint URL (e.g., "http://localhost:11434")
    /// - Returns: Tuple with host, port, and scheme
    internal func parseEndpoint(_ endpoint: String) -> (host: String, port: Int, scheme: String) {
        let cleanedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanedEndpoint), let host = url.host else {
            Logger.llm.error("Invalid endpoint URL: \(endpoint)")
            return ("api.openai.com", 443, "https")
        }

        let scheme = url.scheme ?? "https"
        guard ["http", "https"].contains(scheme.lowercased()) else {
             Logger.llm.error("Unsupported scheme: \(scheme)")
             return ("api.openai.com", 443, "https")
        }

        let port: Int
        if let urlPort = url.port {
            port = urlPort
        } else {
            port = (scheme == "https") ? 443 : 80
        }

        return (host, port, scheme)
    }
}

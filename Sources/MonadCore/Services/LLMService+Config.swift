import Foundation
import OSLog
import OpenAI

extension LLMService {
    // MARK: - Internal Configuration Helpers

    /// Update LLM client with configuration
    internal func updateClient(with config: LLMConfiguration) {
        Logger.llm.debug("Updating clients for provider: \(config.provider.rawValue)")

        switch config.provider {
        case .ollama:
            self.setClients(
                main: OllamaClient(endpoint: config.endpoint, modelName: config.modelName),
                utility: OllamaClient(endpoint: config.endpoint, modelName: config.utilityModel),
                fast: OllamaClient(endpoint: config.endpoint, modelName: config.fastModel)
            )

        case .openRouter:
            let components = parseEndpoint(config.endpoint)
            self.setClients(
                main: OpenRouterClient(
                    apiKey: config.apiKey,
                    modelName: config.modelName,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme
                ),
                utility: OpenRouterClient(
                    apiKey: config.apiKey,
                    modelName: config.utilityModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme
                ),
                fast: OpenRouterClient(
                    apiKey: config.apiKey,
                    modelName: config.fastModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme
                )
            )

        case .openAI, .openAICompatible:
            let components = parseEndpoint(config.endpoint)
            self.setClients(
                main: OpenAIClient(
                    apiKey: config.apiKey,
                    modelName: config.modelName,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme
                ),
                utility: OpenAIClient(
                    apiKey: config.apiKey,
                    modelName: config.utilityModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme
                ),
                fast: OpenAIClient(
                    apiKey: config.apiKey,
                    modelName: config.fastModel,
                    host: components.host,
                    port: components.port,
                    scheme: components.scheme
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

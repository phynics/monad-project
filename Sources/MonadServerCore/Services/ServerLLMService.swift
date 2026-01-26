import Foundation
import MonadCore
import OSLog
import OpenAI

public actor ServerLLMService {
    private var configuration: LLMConfiguration = .openAI
    private var client: (any LLMClientProtocol)?
    private var utilityClient: (any LLMClientProtocol)?
    private var fastClient: (any LLMClientProtocol)?
    
    private let storage: ConfigurationStorage
    public let promptBuilder: PromptBuilder
    private let logger = Logger(subsystem: "com.monad.server", category: "LLMService")
    
    public init(storage: ConfigurationStorage = ConfigurationStorage(), promptBuilder: PromptBuilder = PromptBuilder()) {
        self.storage = storage
        self.promptBuilder = promptBuilder
    }
    
    public func loadConfiguration() async {
        let config = await storage.load()
        self.configuration = config
        
        if config.isValid {
            updateClient(with: config)
        } else {
            logger.warning("LLM service not yet configured")
        }
    }
    
    public func getConfiguration() -> LLMConfiguration {
        return configuration
    }
    
    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        try await storage.save(config)
        self.configuration = config
        
        if config.isValid {
            updateClient(with: config)
        } else {
            setClients(main: nil, utility: nil, fast: nil)
        }
    }
    
    public func getClient() -> (any LLMClientProtocol)? {
        return client
    }
    
    internal func setClients(main: (any LLMClientProtocol)?, utility: (any LLMClientProtocol)?, fast: (any LLMClientProtocol)?) {
        self.client = main
        self.utilityClient = utility
        self.fastClient = fast
    }
    
    private func updateClient(with config: LLMConfiguration) {
        logger.debug("Updating clients for provider: \(config.provider.rawValue)")

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
    
    private func parseEndpoint(_ endpoint: String) -> (host: String, port: Int, scheme: String) {
        let cleanedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanedEndpoint), let host = url.host else {
            return ("api.openai.com", 443, "https")
        }

        let scheme = url.scheme ?? "https"
        guard ["http", "https"].contains(scheme.lowercased()) else {
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
    
    public func sendMessage(_ content: String, responseFormat: ChatQuery.ResponseFormat? = nil, useUtilityModel: Bool = false) async throws -> String {
        let selectedClient: (any LLMClientProtocol)?
        if useUtilityModel {
            selectedClient = utilityClient ?? client
        } else {
            selectedClient = client
        }
        
        guard let client = selectedClient else {
            throw LLMServiceError.notConfigured
        }
        return try await client.sendMessage(content, responseFormat: responseFormat)
    }
    
    public func chatStream(
        messages: [ChatQuery.ChatCompletionMessageParam],
        tools: [ChatQuery.ChatCompletionToolParam]? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil
    ) async throws -> AsyncThrowingStream<ChatStreamResult, Error> {
        guard let client = client else {
            throw LLMServiceError.notConfigured
        }
        return await client.chatStream(messages: messages, tools: tools, responseFormat: responseFormat)
    }
    
    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [Note],
        documents: [DocumentContext] = [],
        memories: [Memory] = [],
        chatHistory: [Message],
        tools: [MonadCore.Tool] = [],
        systemInstructions: String? = nil,
        responseFormat: ChatQuery.ResponseFormat? = nil,
        useFastModel: Bool = false
    ) async throws -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>, 
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let clientToUse = useFastModel ? (fastClient ?? client) : client
        
        guard let client = clientToUse else {
            throw LLMServiceError.notConfigured
        }

        // Build prompt with all components
        let (messages, rawPrompt, structuredContext) = await promptBuilder.buildPrompt(
            systemInstructions: systemInstructions,
            contextNotes: contextNotes,
            documents: documents,
            memories: memories,
            tools: tools,
            chatHistory: chatHistory,
            userQuery: userQuery
        )

        // Delegate to client for streaming
        let toolParams = tools.isEmpty ? nil : tools.map { $0.toToolParam() }
        let stream = await client.chatStream(messages: messages, tools: toolParams, responseFormat: responseFormat)

        return (stream, rawPrompt, structuredContext)
    }

    public func generateTags(for text: String) async throws -> [String] {
        let clientToUse = utilityClient ?? client
        guard let client = clientToUse else {
            throw LLMServiceError.notConfigured
        }
        
        let prompt = "Generate a comma-separated list of 1-3 highly relevant tags for the following user query. Return ONLY the tags, nothing else.\n\nQuery: \(text)"
        let response = try await client.sendMessage(prompt, responseFormat: nil)
        
        return response.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

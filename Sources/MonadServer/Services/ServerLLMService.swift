import Foundation
import Logging
import MonadCore
import OpenAI

public actor ServerLLMService: LLMServiceProtocol {
    public private(set) var configuration: LLMConfiguration = .openAI
    public private(set) var isConfigured: Bool = false

    private var client: (any LLMClientProtocol)?
    private var utilityClient: (any LLMClientProtocol)?
    private var fastClient: (any LLMClientProtocol)?

    private let storage: ConfigurationStorage
    public let promptBuilder: PromptBuilder
    private let logger = Logger.server

    public init(
        storage: ConfigurationStorage = ConfigurationStorage(),
        promptBuilder: PromptBuilder = PromptBuilder()
    ) {
        self.storage = storage
        self.promptBuilder = promptBuilder
    }

    public func loadConfiguration() async {
        let config = await storage.load()
        self.configuration = config
        self.isConfigured = config.isValid

        if config.isValid {
            updateClient(with: config)
        } else {
            logger.warning("LLM service not yet configured")
        }
    }

    public func updateConfiguration(_ config: LLMConfiguration) async throws {
        try await storage.save(config)
        self.configuration = config
        self.isConfigured = config.isValid

        if config.isValid {
            updateClient(with: config)
        } else {
            setClients(main: nil, utility: nil, fast: nil)
        }
    }

    public func clearConfiguration() async {
        await storage.clear()
        self.configuration = .openAI
        self.isConfigured = false
        setClients(main: nil, utility: nil, fast: nil)
    }

    public func restoreFromBackup() async throws {
        if let restored = try await storage.restoreFromBackup() {
            self.configuration = restored
            self.isConfigured = restored.isValid
            if restored.isValid {
                updateClient(with: restored)
            }
        }
    }

    public func exportConfiguration() async throws -> Data {
        try await storage.exportConfiguration()
    }

    public func importConfiguration(from data: Data) async throws {
        try await storage.importConfiguration(from: data)
        await loadConfiguration()
    }

    public func getClient() -> (any LLMClientProtocol)? {
        return client
    }

    internal func setClients(
        main: (any LLMClientProtocol)?, utility: (any LLMClientProtocol)?,
        fast: (any LLMClientProtocol)?
    ) {
        self.client = main
        self.utilityClient = utility
        self.fastClient = fast
    }

    private func updateClient(with config: LLMConfiguration) {
        logger.debug("Updating clients for provider: \(config.provider.rawValue)")

        let components = parseEndpoint(config.endpoint)

        switch config.provider {
        case .ollama:
            self.setClients(
                main: OllamaClient(endpoint: config.endpoint, modelName: config.modelName),
                utility: OllamaClient(endpoint: config.endpoint, modelName: config.utilityModel),
                fast: OllamaClient(endpoint: config.endpoint, modelName: config.fastModel)
            )

        case .openRouter:
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

    public func sendMessage(_ content: String) async throws -> String {
        try await sendMessage(content, responseFormat: nil, useUtilityModel: false)
    }

    public func sendMessage(
        _ content: String, responseFormat: ChatQuery.ResponseFormat? = nil,
        useUtilityModel: Bool = false
    ) async throws -> String {
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
    ) async -> AsyncThrowingStream<ChatStreamResult, Error> {
        guard let client = client else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
        }
        return await client.chatStream(
            messages: messages, tools: tools, responseFormat: responseFormat)
    }

    public func chatStreamWithContext(
        userQuery: String,
        contextNotes: [ContextFile],
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [any MonadCore.Tool],
        systemInstructions: String?,
        responseFormat: ChatQuery.ResponseFormat?,
        useFastModel: Bool
    ) async -> (
        stream: AsyncThrowingStream<ChatStreamResult, Error>,
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        let clientToUse = useFastModel ? (fastClient ?? client) : client

        guard let client = clientToUse else {
            let stream = AsyncThrowingStream<ChatStreamResult, Error> { continuation in
                continuation.finish(throwing: LLMServiceError.notConfigured)
            }
            return (stream, "Error: Not configured", [:])
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
        let stream = await client.chatStream(
            messages: messages, tools: toolParams, responseFormat: responseFormat)

        return (stream, rawPrompt, structuredContext)
    }

    public func buildPrompt(
        userQuery: String,
        contextNotes: [ContextFile],
        documents: [DocumentContext],
        memories: [Memory],
        chatHistory: [Message],
        tools: [any MonadCore.Tool],
        systemInstructions: String?
    ) async -> (
        messages: [ChatQuery.ChatCompletionMessageParam],
        rawPrompt: String,
        structuredContext: [String: String]
    ) {
        await promptBuilder.buildPrompt(
            systemInstructions: systemInstructions,
            contextNotes: contextNotes,
            documents: documents,
            memories: memories,
            tools: tools,
            chatHistory: chatHistory,
            userQuery: userQuery
        )
    }

    public func generateTags(for text: String) async throws -> [String] {
        guard let client = utilityClient ?? client else {
            return []
        }

        let prompt = """
            Extract 3-5 relevant keywords or tags from the following text.
            Return ONLY a JSON object with a key "tags" containing an array of strings.

            Text:
            \(text)
            """

        do {
            let response = try await client.sendMessage(prompt, responseFormat: .jsonObject)

            // Clean up response
            var cleanJson = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanJson.hasPrefix("```json") {
                cleanJson = cleanJson.replacingOccurrences(of: "```json", with: "")
            }
            if cleanJson.hasPrefix("```") {
                cleanJson = cleanJson.replacingOccurrences(of: "```", with: "")
            }
            cleanJson = cleanJson.trimmingCharacters(in: .whitespacesAndNewlines)

            struct TagResponse: Codable {
                let tags: [String]
            }

            guard let data = cleanJson.data(using: .utf8),
                let tagResponse = try? JSONDecoder().decode(TagResponse.self, from: data)
            else {
                logger.warning("Failed to parse tags from LLM response: \(response)")
                return []
            }

            return tagResponse.tags.map { $0.lowercased() }
        } catch {
            logger.error("Failed to generate tags: \(error.localizedDescription)")
            return []
        }
    }

    public func generateTitle(for messages: [Message]) async throws -> String {
        guard let client = utilityClient ?? client, !messages.isEmpty else {
            return "New Conversation"
        }

        let transcript = messages.map { "[\($0.role.rawValue.uppercased())] \($0.content)" }.joined(
            separator: "\n\n")

        let prompt = """
            Based on the following conversation transcript, generate a concise, descriptive title (maximum 6 words).
            Return ONLY the title text, no quotes or additional formatting.

            TRANSCRIPT:
            \(transcript)
            """

        do {
            let response = try await client.sendMessage(prompt, responseFormat: nil)
            let title = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")

            return title.isEmpty ? "New Conversation" : title
        } catch {
            logger.error("Failed to generate title: \(error.localizedDescription)")
            return "New Conversation"
        }
    }

    public func evaluateRecallPerformance(transcript: String, recalledMemories: [Memory])
        async throws -> [String: Double]
    {
        guard let client = utilityClient ?? client, !recalledMemories.isEmpty else {
            return [:]
        }

        let memoriesText = recalledMemories.map {
            "- ID: \($0.id.uuidString)\n  Title: \($0.title)\n  Content: \($0.content)"
        }.joined(separator: "\n\n")

        let prompt = """
            Analyze the following conversation transcript and the list of recalled memories that were provided to you as context.
            Determine for EACH memory if it was actually useful for answering the user's questions or providing relevant context.

            RECALLED MEMORIES:
            \(memoriesText)

            TRANSCRIPT:
            \(transcript)

            Return ONLY a JSON object where keys are memory IDs and values are helpfulness scores (numbers between -1.0 and 1.0):
            1.0: Extremely helpful, directly used to answer.
            0.5: Somewhat helpful, provided good context.
            0.0: Neutral, didn't hurt but wasn't used.
            -0.5: Irrelevant, slightly off-topic.
            -1.0: Completely irrelevant or misleading.
            """

        do {
            let response = try await client.sendMessage(prompt, responseFormat: .jsonObject)

            // Clean up response
            var cleanJson = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanJson.hasPrefix("```json") {
                cleanJson = cleanJson.replacingOccurrences(of: "```json", with: "")
            }
            if cleanJson.hasPrefix("```") {
                cleanJson = cleanJson.replacingOccurrences(of: "```", with: "")
            }
            cleanJson = cleanJson.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = cleanJson.data(using: .utf8),
                let scores = try? JSONDecoder().decode([String: Double].self, from: data)
            else {
                logger.warning("Failed to parse recall evaluation from LLM response: \(response)")
                return [:]
            }

            return scores
        } catch {
            logger.error("Failed to evaluate recall: \(error.localizedDescription)")
            return [:]
        }
    }

    public func fetchAvailableModels() async throws -> [String]? {
        guard let client = client else {
            return nil
        }
        return try await client.fetchAvailableModels()
    }
}

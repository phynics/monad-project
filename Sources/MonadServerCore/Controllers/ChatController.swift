import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore
import Logging
import OpenAI

public struct ChatRequest: Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct ChatResponse: Codable, Sendable, ResponseGenerator {
    public let response: String

    public init(response: String) {
        self.response = response
    }

    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

public struct ChatController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    public let llmService: any LLMServiceProtocol
    public let verbose: Bool

    public init(
        sessionManager: SessionManager, llmService: any LLMServiceProtocol, verbose: Bool = false
    ) {
        self.sessionManager = sessionManager
        self.llmService = llmService
        self.verbose = verbose
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/{id}/chat", use: chat)
        group.post("/{id}/chat/stream", use: chatStream)
    }

    @Sendable func chat(_ request: Request, context: Context) async throws -> ChatResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)

        guard await sessionManager.getSession(id: id) != nil else {
            throw HTTPError(.notFound)
        }

        let persistence = await sessionManager.getPersistenceService()
        let contextManager = await sessionManager.getContextManager(for: id)

        // 1. Save User Message
        let userMsg = ConversationMessage(sessionId: id, role: .user, content: chatRequest.message)
        try await persistence.saveMessage(userMsg)

        // 2. Fetch History
        let history = try await sessionManager.getHistory(for: id)

        // 3. Gather Context
        var contextData = ContextData()
        if let contextManager = contextManager {
            contextData = try await contextManager.gatherContext(
                for: chatRequest.message,
                history: history,
                tagGenerator: { [llmService] query in
                    try await llmService.generateTags(for: query)
                }
            )
        }

        // 4. Send Message with Context
        guard await llmService.isConfigured else {
            throw HTTPError(.serviceUnavailable)
        }

        let (stream, _, _) = try await llmService.chatStreamWithContext(
            userQuery: chatRequest.message,
            contextNotes: contextData.notes,
            documents: [],
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: [],
            systemInstructions: nil,
            responseFormat: nil,
            useFastModel: false
        )

        var fullResponse = ""
        for try await result in stream {
            if let delta = result.choices.first?.delta.content {
                fullResponse += delta
            }
        }

        // 5. Save Assistant Message
        let recalledMemoriesData = try SerializationUtils.jsonEncoder.encode(
            contextData.memories.map { $0.memory })
        let recalledMemoriesString = String(decoding: recalledMemoriesData, as: UTF8.self)
        let assistantMsg = ConversationMessage(
            sessionId: id,
            role: .assistant,
            content: fullResponse,
            recalledMemories: recalledMemoriesString
        )
        try await persistence.saveMessage(assistantMsg)

        return ChatResponse(response: fullResponse)
    }

    @Sendable func chatStream(_ request: Request, context: Context) async throws -> Response {
        if verbose { Logger.chat.debug("chatStream called") }
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            if verbose { Logger.chat.debug("Invalid UUID: \(idString)") }
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)
        if verbose { Logger.chat.debug("Received message: \(chatRequest.message)") }

        guard await sessionManager.getSession(id: id) != nil else {
            if verbose { Logger.chat.debug("Session not found: \(id)") }
            throw HTTPError(.notFound)
        }

        let persistence = await sessionManager.getPersistenceService()
        let contextManager = await sessionManager.getContextManager(for: id)

        // 1. Save User Message
        let userMsg = ConversationMessage(sessionId: id, role: .user, content: chatRequest.message)
        try await persistence.saveMessage(userMsg)

        // 2. Fetch History
        let history = try await sessionManager.getHistory(for: id)
        if verbose { Logger.chat.debug("History fetched, count: \(history.count)") }

        // 3. Gather Context
        var contextData = ContextData()
        if let contextManager = contextManager {
            if verbose { Logger.chat.debug("Gathering context...") }
            contextData = try await contextManager.gatherContext(
                for: chatRequest.message,
                history: history,
                tagGenerator: { [llmService] query in
                    try await llmService.generateTags(for: query)
                }
            )
            if verbose {
                Logger.chat.debug(
                    "Context gathered. Memories: \(contextData.memories.count), Notes: \(contextData.notes.count)"
                )
            }
        } else {
            if verbose { Logger.chat.debug("No ContextManager found") }
        }

        guard await llmService.isConfigured else {
            if verbose { Logger.chat.debug("LLM Service not configured") }
            throw HTTPError(.serviceUnavailable)
        }

        if verbose { Logger.chat.debug("calling chatStreamWithContext") }
        let streamData = try await llmService.chatStreamWithContext(
            userQuery: chatRequest.message,
            contextNotes: contextData.notes,
            documents: [],
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: [],
            systemInstructions: nil,
            responseFormat: nil,
            useFastModel: false
        )

        let memories = contextData.memories.map { $0.memory }

        let sseStream = AsyncStream<ByteBuffer> { continuation in
            Task { [id, persistence, memories] in
                do {
                    if verbose { Logger.chat.debug("Starting stream processing task") }
                    var fullResponse = ""
                    for try await result in streamData.stream {
                        if let delta = result.choices.first?.delta.content {
                            fullResponse += delta
                            if verbose { Logger.chat.debug("Sending delta: \(delta)") }
                        }
                        if let data = try? SerializationUtils.jsonEncoder.encode(result) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    }
                    if verbose {
                        Logger.chat.debug(
                            "Stream complete. Full response length: \(fullResponse.count)")
                    }

                    // 5. Save Assistant Message
                    let recalledMemoriesData = try? SerializationUtils.jsonEncoder.encode(memories)
                    let recalledMemoriesString =
                        recalledMemoriesData.flatMap { String(decoding: $0, as: UTF8.self) } ?? "[]"
                    let assistantMsg = ConversationMessage(
                        sessionId: id,
                        role: .assistant,
                        content: fullResponse,
                        recalledMemories: recalledMemoriesString
                    )
                    try? await persistence.saveMessage(assistantMsg)

                    continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
                    continuation.finish()
                } catch {
                    if verbose { Logger.chat.debug("Error in stream: \(error)") }
                    continuation.finish()
                }
            }
        }

        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        headers[.connection] = "keep-alive"

        return Response(status: .ok, headers: headers, body: .init(asyncSequence: sseStream))
    }
}

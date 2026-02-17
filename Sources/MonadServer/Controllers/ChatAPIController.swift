import Foundation
import HTTPTypes
import Hummingbird
import Logging
import MonadCore
import MonadShared
import NIOCore
import OpenAI

extension ChatResponse: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

public struct ChatAPIController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    public let chatEngine: ChatEngine
    public let toolRouter: ToolRouter
    public let verbose: Bool

    public init(
        sessionManager: SessionManager,
        chatEngine: ChatEngine,
        toolRouter: ToolRouter,
        verbose: Bool = false
    ) {
        self.sessionManager = sessionManager
        self.chatEngine = chatEngine
        self.toolRouter = toolRouter
        self.verbose = verbose
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/{id}/chat", use: chat)
        group.post("/{id}/chat/stream", use: chatStream)
        group.get("/{id}/chat/debug", use: getDebug)
    }

    @Sendable func chat(_ request: Request, context: Context) async throws -> ChatResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: MonadShared.ChatRequest.self, context: context)

        // Hydrate session and resolve tools at the server layer
        try await sessionManager.hydrateSession(id: id)
        let availableTools = await resolveTools(sessionId: id, clientId: chatRequest.clientId)

        let stream = try await chatEngine.chatStream(
            sessionId: id,
            message: chatRequest.message,
            tools: availableTools,
            toolOutputs: chatRequest.toolOutputs?.map { .init(toolCallId: $0.toolCallId, output: $0.output) }
        )

        var fullResponse = ""
        for try await event in stream {
            switch event {
            case .delta(let content):
                fullResponse += content
            case .completion(let content):
                fullResponse = content
            default:
                break
            }
        }

        return ChatResponse(response: fullResponse)
    }

    @Sendable func chatStream(_ request: Request, context: Context) async throws -> Response {
        if verbose { Logger.chat.debug("chatStream called") }
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: MonadShared.ChatRequest.self, context: context)

        // Hydrate session and resolve tools at the server layer
        try await sessionManager.hydrateSession(id: id)
        let availableTools = await resolveTools(sessionId: id, clientId: chatRequest.clientId)

        let chatEngineStream = try await chatEngine.chatStream(
            sessionId: id,
            message: chatRequest.message,
            tools: availableTools,
            toolOutputs: chatRequest.toolOutputs?.map { .init(toolCallId: $0.toolCallId, output: $0.output) }
        )

        let sseStream = AsyncStream<ByteBuffer> { continuation in
            Task {
                do {
                    for try await event in chatEngineStream {
                        let apiDelta: MonadShared.ChatDelta
                        switch event {
                        case .delta(let content):
                            apiDelta = MonadShared.ChatDelta(content: content)
                        case .thought(let content):
                            apiDelta = MonadShared.ChatDelta(thought: content)
                        case .toolCall(let tc):
                            apiDelta = MonadShared.ChatDelta(toolCalls: [
                                MonadShared.ToolCallDelta(index: tc.index, id: tc.id, name: tc.name, arguments: tc.arguments)
                            ])
                        case .metadata(let m):
                            apiDelta = MonadShared.ChatDelta(metadata: MonadShared.ChatMetadata(memories: m.memories, files: m.files))
                        case .completion:
                            apiDelta = MonadShared.ChatDelta(isDone: true)
                        case .error(let e):
                            apiDelta = MonadShared.ChatDelta(error: e)
                        case .toolResult:
                            continue  // Not sent to client
                        }
                        if let data = try? SerializationUtils.jsonEncoder.encode(apiDelta) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    }
                    continuation.finish()
                } catch {
                    Logger.chat.error("Stream error: \(error)")
                    let errorDelta = MonadShared.ChatDelta(error: error.localizedDescription)
                    if let data = try? SerializationUtils.jsonEncoder.encode(errorDelta) {
                        let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                        continuation.yield(ByteBuffer(string: sseString))
                    }
                    continuation.finish()
                }
            }
        }

        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        return Response(status: .ok, headers: headers, body: .init(asyncSequence: sseStream))
    }

    @Sendable func getDebug(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }

        guard let snapshot = await sessionManager.getDebugSnapshot(for: id) else {
            throw HTTPError(.notFound)
        }

        let data = try SerializationUtils.jsonEncoder.encode(snapshot)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    // MARK: - Tool Resolution (Server-Layer Concern)

    private func resolveTools(sessionId: UUID, clientId: UUID?) async -> [AnyTool] {
        var availableTools: [AnyTool] = []
        do {
            let references = try await sessionManager.getAllToolReferences(sessionId: sessionId, clientId: clientId)
            
            availableTools = references.compactMap { (ref: ToolReference) -> AnyTool? in
                var def: WorkspaceToolDefinition?
                switch ref {
                case .known(let id): def = SystemToolRegistry.shared.getDefinition(for: id)
                case .custom(let definition): def = definition
                }
                guard let d = def else { return nil }
                return AnyTool(DelegatingTool(
                    ref: ref,
                    router: toolRouter,
                    sessionId: sessionId,
                    resolvedDefinition: d
                ))
            }
        } catch {
            Logger.chat.warning("Failed to fetch tools: \(error)")
        }
        return availableTools
    }
}


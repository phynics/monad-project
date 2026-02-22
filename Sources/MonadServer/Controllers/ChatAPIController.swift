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
            case .generationCompleted(let message, _):
                fullResponse = message.content
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
            let task = Task {
                do {
                    for try await event in chatEngineStream {
                        let apiDelta: MonadShared.ChatDelta
                        switch event {
                        case .generationContext(let m):
                            apiDelta = MonadShared.ChatDelta(type: .generationContext, metadata: m)
                        case .delta(let content):
                            apiDelta = MonadShared.ChatDelta(type: .delta, content: content)
                        case .thought(let content):
                            apiDelta = MonadShared.ChatDelta(type: .thought, thought: content)
                        case .thoughtCompleted:
                            apiDelta = MonadShared.ChatDelta(type: .thoughtCompleted)
                        case .toolCall(let tc):
                            apiDelta = MonadShared.ChatDelta(type: .toolCall, toolCalls: [tc])
                        case .toolCallError(let id, let name, let error):
                            apiDelta = MonadShared.ChatDelta(
                                type: .toolCallError,
                                toolCallError: MonadShared.ToolCallErrorDelta(
                                    toolCallId: id,
                                    name: name,
                                    error: error
                                )
                            )
                        case .toolExecution(let id, let status):
                            let statusStr: String
                            var name: String?
                            var target: String?
                            var resultStr: String?
                            
                            switch status {
                            case .attempting(let n, let ref):
                                statusStr = "attempting"
                                name = n
                                switch ref {
                                case .known:
                                    target = "server"
                                case .custom:
                                    target = "client"
                                }
                            case .success(let res):
                                statusStr = "success"
                                resultStr = res.output
                            case .failure(let err):
                                statusStr = "failure"
                                resultStr = err.localizedDescription
                            }
                            
                            apiDelta = MonadShared.ChatDelta(
                                type: .toolExecution,
                                toolExecution: MonadShared.ToolExecutionDelta(
                                    toolCallId: id,
                                    status: statusStr,
                                    name: name,
                                    target: target,
                                    result: resultStr
                                )
                            )
                        case .generationCompleted(_, let meta):
                            let apiMeta = MonadShared.APIMetadataDelta(
                                model: meta.model,
                                promptTokens: meta.promptTokens,
                                completionTokens: meta.completionTokens,
                                totalTokens: meta.totalTokens,
                                finishReason: meta.finishReason,
                                systemFingerprint: meta.systemFingerprint,
                                duration: meta.duration,
                                tokensPerSecond: meta.tokensPerSecond,
                                debugSnapshotData: meta.debugSnapshotData
                            )
                            apiDelta = MonadShared.ChatDelta(type: .generationCompleted, responseMetadata: apiMeta)
                        case .error(let e):
                            apiDelta = MonadShared.ChatDelta(type: .error, error: e.localizedDescription)
                        }
                        
                        if let data = try? SerializationUtils.jsonEncoder.encode(apiDelta) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    }
                    
                    // Signal end of stream
                    let doneDelta = MonadShared.ChatDelta(type: .streamCompleted)
                    if let data = try? SerializationUtils.jsonEncoder.encode(doneDelta) {
                        let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                        continuation.yield(ByteBuffer(string: sseString))
                    }
                    
                    continuation.finish()
                } catch {
                    if !(error is CancellationError) {
                        Logger.chat.error("Stream error: \(error)")
                        let errorDelta = MonadShared.ChatDelta(type: .error, error: error.localizedDescription)
                        if let data = try? SerializationUtils.jsonEncoder.encode(errorDelta) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    }
                    continuation.finish()
                }
            }
            
            continuation.onTermination = { @Sendable _ in
                task.cancel()
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


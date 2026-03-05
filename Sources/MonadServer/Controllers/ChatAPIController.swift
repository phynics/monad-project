import Foundation
import HTTPTypes
import Hummingbird
import Logging
import MonadCore
import MonadShared
import NIOCore
import OpenAI

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
        group.post("/{id}/chat/cancel", use: cancel)
        group.get("/{id}/chat/debug", use: getDebug)
    }

    @Sendable func chat(_ request: Request, context: Context) async throws -> ChatResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)

        // Hydrate session and resolve tools at the server layer
        try await sessionManager.hydrateSession(id: id)
        let availableTools = await resolveTools(sessionId: id, clientTools: chatRequest.clientTools)

        let stream = try await chatEngine.chatStream(
            sessionId: id,
            message: chatRequest.message,
            tools: availableTools,
            toolOutputs: chatRequest.toolOutputs?.map { .init(toolCallId: $0.toolCallId, output: $0.output) }
        )

        var fullResponse = ""
        for try await event in stream {
            if let text = event.textContent {
                fullResponse += text
            } else if let completed = event.completedMessage {
                fullResponse = completed.message.content
            }
        }

        return ChatResponse(response: fullResponse)
    }

    @Sendable func chatStream(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)

        let sid = ANSIColors.colorize(id.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
        Logger.module(named: "chat").info("Streaming chat in session \(sid)")

        // Hydrate session and resolve tools at the server layer
        try await sessionManager.hydrateSession(id: id)
        let availableTools = await resolveTools(sessionId: id, clientTools: chatRequest.clientTools)

        Logger.module(named: "chat").info("Resolved \(ANSIColors.colorize("\(availableTools.count)", color: ANSIColors.green)) tools for session \(sid)")

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
                        if Task.isCancelled {
                            throw CancellationError()
                        }

                        if let data = try? SerializationUtils.jsonEncoder.encode(event) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    }

                    if Task.isCancelled {
                        throw CancellationError()
                    }

                    // Signal end of stream
                    let doneEvent = ChatEvent.streamCompleted()
                    if let data = try? SerializationUtils.jsonEncoder.encode(doneEvent) {
                        let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                        continuation.yield(ByteBuffer(string: sseString))
                    }

                    continuation.finish()
                } catch {
                    if error is CancellationError {
                        let cancelEvent = ChatEvent.cancelled()
                        if let data = try? SerializationUtils.jsonEncoder.encode(cancelEvent) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    } else {
                        Logger.module(named: "chat").error("Stream error: \(error)")
                        let errorEvent = ChatEvent.error(error.localizedDescription)
                        if let data = try? SerializationUtils.jsonEncoder.encode(errorEvent) {
                            let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                            continuation.yield(ByteBuffer(string: sseString))
                        }
                    }
                    continuation.finish()
                }
            }

            let registrationTask = task
            Task {
                await sessionManager.registerTask(registrationTask, for: id)
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

    @Sendable func cancel(_ request: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }
        await sessionManager.cancelGeneration(for: id)
        return Response(status: .ok)
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

    private func resolveTools(sessionId: UUID, clientTools: [ToolReference]?) async -> [AnyTool] {
        var availableTools: [AnyTool] = []
        do {
            let references = try await sessionManager.getAllToolReferences(sessionId: sessionId, clientTools: clientTools)

            availableTools = references.compactMap { (ref: ToolReference) -> AnyTool? in
                var def: WorkspaceToolDefinition?
                switch ref {
                case .known(let id): def = SystemToolRegistry.shared.getDefinition(for: id)
                case .custom(let definition): def = definition
                }
                guard let definition = def else { return nil }
                return AnyTool(DelegatingTool(
                    ref: ref,
                    router: toolRouter,
                    sessionId: sessionId,
                    resolvedDefinition: definition
                ))
            }
        } catch {
            Logger.module(named: "chat").error("Failed to resolve tools for session \(sessionId): \(error)")
        }
        return availableTools
    }
}

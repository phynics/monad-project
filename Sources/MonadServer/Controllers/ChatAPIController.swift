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
    public let chatOrchestrator: ChatOrchestrator
    public let verbose: Bool

    public init(
        sessionManager: SessionManager,
        chatOrchestrator: ChatOrchestrator,
        verbose: Bool = false
    ) {
        self.sessionManager = sessionManager
        self.chatOrchestrator = chatOrchestrator
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

        let stream = try await chatOrchestrator.chatStream(
            sessionId: id,
            message: chatRequest.message,
            clientId: chatRequest.clientId,
            toolOutputs: chatRequest.toolOutputs?.map { .init(toolCallId: $0.toolCallId, output: $0.output) }
        )

        var fullResponse = ""
        for try await delta in stream {
            if let content = delta.content {
                fullResponse += content
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

        let chatOrchestratorStream = try await chatOrchestrator.chatStream(
            sessionId: id,
            message: chatRequest.message,
            clientId: chatRequest.clientId,
            toolOutputs: chatRequest.toolOutputs?.map { .init(toolCallId: $0.toolCallId, output: $0.output) }
        )

        let sseStream = AsyncStream<ByteBuffer> { continuation in
            Task {
                do {
                    for try await coreDelta in chatOrchestratorStream {
                        let apiDelta = MonadShared.ChatDelta(fromCore: coreDelta)
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
}

extension MonadShared.ChatDelta {
    init(fromCore delta: MonadCore.ChatDelta) {
        self.init(
            content: delta.content,
            thought: delta.thought,
            toolCalls: delta.toolCalls?.map { .init(fromCore: $0) },
            metadata: delta.metadata.map { .init(fromCore: $0) },
            error: delta.error,
            isDone: delta.isDone
        )
    }
}

extension MonadShared.ToolCallDelta {
    init(fromCore delta: MonadCore.ToolCallDelta) {
        self.init(
            index: delta.index,
            id: delta.id,
            name: delta.name,
            arguments: delta.arguments
        )
    }
}

extension MonadShared.ChatMetadata {
    init(fromCore metadata: MonadCore.ChatMetadata) {
        self.init(
            memories: metadata.memories,
            files: metadata.files
        )
    }
}

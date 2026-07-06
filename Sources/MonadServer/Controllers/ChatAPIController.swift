import Foundation
import HTTPTypes
import Hummingbird
import Logging
import PositronicKit
import PKShared
import MonadShared
import NIOCore

public struct ChatAPIController<Context: RequestContext>: Sendable {
    private let timelineManager: TimelineManager
    private let agentInstanceStore: any AgentInstanceStoreProtocol
    private let toolRouter: ToolRouter
    private let chat: PositronicKit
    public let verbose: Bool
    private let logger = Logger.module(named: "chat")

    public init(
        chat: PositronicKit,
        timelineManager: TimelineManager,
        agentInstanceStore: any AgentInstanceStoreProtocol,
        toolRouter: ToolRouter,
        verbose: Bool = false
    ) {
        self.chat = chat
        self.timelineManager = timelineManager
        self.agentInstanceStore = agentInstanceStore
        self.toolRouter = toolRouter
        self.verbose = verbose
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/{id}/chat", use: chat)
        group.post("/{id}/chat/stream", use: chatStream)
        group.post("/{id}/chat/cancel", use: cancel)
    }

    @Sendable func chat(_ request: Request, context: Context) async throws -> ChatResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)

        // Hydrate timeline and resolve tools at the server layer
        try await timelineManager.hydrateTimeline(id: id)

        guard let agent = try await attachedAgent(for: id) else {
            throw HTTPError(
                .unprocessableContent,
                message: "No agent attached to timeline. Attach an agent before sending messages."
            )
        }
        let availableTools = await resolveTools(timelineId: id, attachedTools: chatRequest.attachedTools)

        let stream = try await chat.run(ChatRunRequest(
            timelineId: id,
            message: chatRequest.message,
            tools: availableTools,
            toolOutputs: chatRequest.toolOutputs,
            systemInstructions: MonadSystemInstructions.system(),
            agentInstanceId: agent.id
        ))

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
        logger.info("Streaming chat in timeline \(sid)")

        let chatStream = try await prepareAndExecuteChat(
            timelineId: id, chatRequest: chatRequest, sid: sid
        )

        let sseStream = buildSSEStream(
            from: chatStream, timelineId: id
        )

        return buildSSEResponse(body: sseStream)
    }

    private func prepareAndExecuteChat(
        timelineId: UUID,
        chatRequest: ChatRequest,
        sid: String
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        try await timelineManager.hydrateTimeline(id: timelineId)

        guard let agent = try await attachedAgent(for: timelineId) else {
            throw HTTPError(
                .unprocessableContent,
                message: "No agent attached to timeline. Attach an agent before sending messages."
            )
        }
        let availableTools = await resolveTools(timelineId: timelineId, attachedTools: chatRequest.attachedTools)

        let toolCountStr = ANSIColors.colorize("\(availableTools.count)", color: ANSIColors.green)
        logger.info("Resolved \(toolCountStr) tools for timeline \(sid)")

        return try await chat.run(ChatRunRequest(
            timelineId: timelineId,
            message: chatRequest.message,
            tools: availableTools,
            toolOutputs: chatRequest.toolOutputs,
            systemInstructions: MonadSystemInstructions.system(),
            agentInstanceId: agent.id
        ))
    }

    private func buildSSEStream(
        from chatStream: AsyncThrowingStream<ChatEvent, Error>,
        timelineId: UUID
    ) -> AsyncStream<ByteBuffer> {
        AsyncStream<ByteBuffer> { continuation in
            let task = Task {
                do {
                    for try await event in chatStream {
                        if Task.isCancelled { throw CancellationError() }
                        yieldSSEEvent(event, to: continuation)
                    }
                    if Task.isCancelled { throw CancellationError() }
                    yieldSSEEvent(ChatEvent.streamCompleted(), to: continuation)
                    continuation.finish()
                } catch {
                    handleStreamError(error, continuation: continuation)
                }
            }

            let registrationTask = task
            Task {
                await timelineManager.registerTask(registrationTask, for: timelineId)
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func yieldSSEEvent(_ event: ChatEvent, to continuation: AsyncStream<ByteBuffer>.Continuation) {
        if verbose {
            logger.debug("Stream delta: \(describe(event: event))")
        }
        if let data = try? SerializationUtils.jsonEncoder.encode(event) {
            let sseString = "data: \(String(bytes: data, encoding: .utf8) ?? "")\n\n"
            continuation.yield(ByteBuffer(string: sseString))
        }
    }

    private func handleStreamError(_ error: Error, continuation: AsyncStream<ByteBuffer>.Continuation) {
        if error is CancellationError {
            yieldSSEEvent(ChatEvent.generationCancelled(), to: continuation)
        } else {
            logger.error("Stream error: \(error)")
            yieldSSEEvent(ChatEvent.error(error.localizedDescription), to: continuation)
        }
        continuation.finish()
    }

    private func describe(event: ChatEvent) -> String {
        switch event {
        case .meta(let meta):
            return "meta=\(String(reflecting: meta))"
        case .delta(let delta):
            return "delta=\(String(reflecting: delta))"
        case .error(let error):
            return "error=\(String(reflecting: error))"
        case .completion(let completion):
            return "completion=\(String(reflecting: completion))"
        }
    }

    private func buildSSEResponse(body: AsyncStream<ByteBuffer>) -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        return Response(status: .ok, headers: headers, body: .init(asyncSequence: body))
    }

    @Sendable func cancel(_: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }
        await timelineManager.cancelGeneration(for: id)
        return Response(status: .ok)
    }

    // MARK: - Tool Resolution (Server-Layer Concern)

    private func resolveTools(timelineId: UUID, attachedTools: [ToolReference]?) async -> [AnyTool] {
        guard let toolManager = await timelineManager.getToolManager(for: timelineId) else {
            return []
        }

        var availableTools = await toolManager.getEnabledTools()
        let knownIDs = Set(availableTools.map(\.id))

        for ref in attachedTools ?? [] where !knownIDs.contains(ref.toolId) {
            var tool = AnyTool(DeferredAttachedTool(reference: ref))
            tool.provenance = .named("Attached")
            availableTools.append(tool)
        }

        return availableTools
    }

    private func attachedAgent(for timelineId: UUID) async throws -> AgentInstance? {
        guard let timeline = await timelineManager.getTimeline(id: timelineId),
              let agentId = timeline.attachedAgentInstanceId else {
            return nil
        }
        return try await agentInstanceStore.fetchAgentInstance(id: agentId)
    }
}

private struct DeferredAttachedTool: PKShared.Tool, ToolReferenceProviding {
    let toolReference: ToolReference

    init(reference: ToolReference) {
        toolReference = reference
    }

    var id: String { toolReference.toolId }

    var name: String {
        switch toolReference {
        case let .known(id): return id
        case let .custom(definition): return definition.name
        }
    }

    var description: String {
        switch toolReference {
        case let .known(id): return "Attached workspace tool: \(id)"
        case let .custom(definition): return definition.description
        }
    }

    var requiresPermission: Bool {
        switch toolReference {
        case .known: return false
        case let .custom(definition): return definition.requiresPermission
        }
    }

    var usageExample: String? {
        switch toolReference {
        case .known: return nil
        case let .custom(definition): return definition.usageExample
        }
    }

    var parametersSchema: [String: AnyCodable] {
        switch toolReference {
        case .known: return [:]
        case let .custom(definition): return definition.parametersSchema
        }
    }

    func canExecute() async -> Bool { true }

    func execute(parameters _: [String: Any]) async throws -> ToolResult {
        .failure("Attached workspace tools are routed externally")
    }
}

import Dependencies
import Foundation
import HTTPTypes
import Hummingbird
import Logging
import MonadCore
import MonadShared
import NIOCore
import OpenAI

public struct ChatAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.timelineManager) var timelineManager: TimelineManager
    @Dependency(\.chatEngine) var chatEngine: ChatEngine
    @Dependency(\.toolRouter) var toolRouter: ToolRouter
    public let verbose: Bool

    public init(verbose: Bool = false) {
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

        // Strict mode: require an agent to be attached
        guard let agent = await timelineManager.getAttachedAgentInstance(for: id) else {
            throw HTTPError(.unprocessableContent, message: "No agent attached to timeline. Attach an agent before sending messages.")
        }
        let systemInstructions = await timelineManager.getAgentSystemInstructions(for: id)
        let availableTools = await resolveTools(timelineId: id, clientTools: chatRequest.clientTools)

        let stream = try await chatEngine.execute(
            timelineId: id,
            message: chatRequest.message,
            tools: availableTools,
            toolOutputs: chatRequest.toolOutputs?.map { .init(toolCallId: $0.toolCallId, output: $0.output) },
            systemInstructions: systemInstructions,
            agentInstanceId: agent.id
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
        Logger.module(named: "chat").info("Streaming chat in timeline \(sid)")

        // Hydrate timeline and resolve tools at the server layer
        try await timelineManager.hydrateTimeline(id: id)

        // Strict mode: require an agent to be attached
        guard let agent = await timelineManager.getAttachedAgentInstance(for: id) else {
            throw HTTPError(.unprocessableContent, message: "No agent attached to timeline. Attach an agent before sending messages.")
        }
        let systemInstructions = await timelineManager.getAgentSystemInstructions(for: id)
        let availableTools = await resolveTools(timelineId: id, clientTools: chatRequest.clientTools)

        Logger.module(named: "chat").info("Resolved \(ANSIColors.colorize("\(availableTools.count)", color: ANSIColors.green)) tools for timeline \(sid)")

        let chatEngineStream = try await chatEngine.execute(
            timelineId: id,
            message: chatRequest.message,
            tools: availableTools,
            toolOutputs: chatRequest.toolOutputs?.map { .init(toolCallId: $0.toolCallId, output: $0.output) },
            systemInstructions: systemInstructions,
            agentInstanceId: agent.id
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
                        let cancelEvent = ChatEvent.generationCancelled()
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
                await timelineManager.registerTask(registrationTask, for: id)
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

    @Sendable func cancel(_: Request, context: Context) async throws -> Response {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }
        await timelineManager.cancelGeneration(for: id)
        return Response(status: .ok)
    }

    // MARK: - Tool Resolution (Server-Layer Concern)

    private func resolveTools(timelineId: UUID, clientTools: [ToolReference]?) async -> [AnyTool] {
        var availableTools: [AnyTool] = []

        // Build a fallback lookup from in-memory system tools so .known refs for workspace-registered
        // filesystem tools (cat, ls, grep, etc.) can be resolved even though SystemToolRegistry only
        // contains always-on system tools (memory_search, web_search).
        let inMemoryLookup: [String: WorkspaceToolDefinition]
        if let toolManager = await timelineManager.getToolManager(for: timelineId) {
            let systemTools = await toolManager.getAvailableTools()
            inMemoryLookup = systemTools.reduce(into: [:]) { dict, tool in
                dict[tool.id] = WorkspaceToolDefinition(
                    id: tool.id,
                    name: tool.name,
                    description: tool.description,
                    parametersSchema: tool.parametersSchema,
                    usageExample: tool.usageExample,
                    requiresPermission: tool.requiresPermission
                )
            }
        } else {
            inMemoryLookup = [:]
        }

        do {
            let references = try await timelineManager.getAllToolReferences(timelineId: timelineId, clientTools: clientTools)

            for ref in references {
                var def: WorkspaceToolDefinition?
                switch ref {
                case let .known(id):
                    def = SystemToolRegistry.shared.getDefinition(for: id) ?? inMemoryLookup[id]
                case let .custom(definition):
                    def = definition
                }
                guard let definition = def else {
                    Logger.module(named: "chat").debug("Skipping tool with no resolvable definition: \(ref.toolId)")
                    continue
                }
                var toolWrapper = AnyTool(DelegatingTool(
                    ref: ref,
                    router: toolRouter,
                    timelineId: timelineId,
                    resolvedDefinition: definition
                ))
                toolWrapper.provenance = await timelineManager.getToolSource(toolId: ref.toolId, for: timelineId)
                availableTools.append(toolWrapper)
            }
        } catch {
            Logger.module(named: "chat").error("Failed to resolve tools for timeline \(timelineId): \(error)")
        }
        return availableTools
    }
}

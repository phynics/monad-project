import Foundation
import HTTPTypes
import Hummingbird
import Logging
import MonadCore
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

public struct ChatController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    public let llmService: any LLMServiceProtocol
    public let toolRouter: ToolRouter?
    public let verbose: Bool

    public init(
        sessionManager: SessionManager,
        llmService: any LLMServiceProtocol,
        toolRouter: ToolRouter? = nil,
        verbose: Bool = false
    ) {
        self.sessionManager = sessionManager
        self.llmService = llmService
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

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)

        var maybeSession = await sessionManager.getSession(id: id)
        if maybeSession == nil {
            try? await sessionManager.hydrateSession(id: id)
            maybeSession = await sessionManager.getSession(id: id)
        }

        guard let session = maybeSession else {
            throw HTTPError(.notFound)
        }

        let persistence = await sessionManager.getPersistenceService()
        let contextManager = await sessionManager.getContextManager(for: id)

        // 1. Save Tool Outputs
        if let toolOutputs = chatRequest.toolOutputs {
            for output in toolOutputs {
                let msg = ConversationMessage(
                    sessionId: id,
                    role: .tool,
                    content: output.output,
                    toolCallId: output.toolCallId
                )
                try await persistence.saveMessage(msg)
            }
        }

        // 2. Save User Message
        if !chatRequest.message.isEmpty {
            let userMsg = ConversationMessage(
                sessionId: id, role: .user, content: chatRequest.message)
            try await persistence.saveMessage(userMsg)
        } else if chatRequest.toolOutputs?.isEmpty ?? true {
            throw HTTPError(.badRequest)
        }

        // 3. Fetch History & Context
        let history = try await sessionManager.getHistory(for: id)

        var contextData = ContextData()
        if let contextManager = contextManager {
            contextData = try await contextManager.gatherContext(
                for: chatRequest.message.isEmpty
                    ? (history.last?.content ?? "") : chatRequest.message,
                history: history,
                tagGenerator: { [llmService] query in try await llmService.generateTags(for: query)
                }
            )
        }

        guard await llmService.isConfigured else { throw HTTPError(.serviceUnavailable) }

        // Load Persona
        var systemInstructions: String? = nil
        if let personaFilename = session.persona, let workingDirectory = session.workingDirectory {
            let personaPath = URL(fileURLWithPath: workingDirectory).appendingPathComponent(
                "Personas"
            ).appendingPathComponent(personaFilename)
            if let content = try? String(contentsOf: personaPath, encoding: .utf8) {
                systemInstructions = content
            }
        }

        // Simple chat uses chatStreamWithContext but collects result (No Tool Loop support for non-streaming yet)
        let (stream, _, _) = await llmService.chatStreamWithContext(
            userQuery: chatRequest.message,
            contextNotes: contextData.notes,
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: [],  // No tools for simple chat
            systemInstructions: systemInstructions,
            responseFormat: nil,
            useFastModel: false
        )

        var fullResponse = ""
        for try await result in stream {
            if let content = result.choices.first?.delta.content {
                fullResponse += content
            }
        }

        let assistantMsg = ConversationMessage(
            sessionId: id,
            role: .assistant,
            content: fullResponse
        )
        try await persistence.saveMessage(assistantMsg)

        return ChatResponse(response: fullResponse)
    }

    @Sendable func chatStream(_ request: Request, context: Context) async throws -> Response {
        if verbose { Logger.chat.debug("chatStream called") }
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)

        var maybeSession = await sessionManager.getSession(id: id)
        if maybeSession == nil {
            try? await sessionManager.hydrateSession(id: id)
            maybeSession = await sessionManager.getSession(id: id)
        }

        guard let session = maybeSession else {
            throw HTTPError(.notFound)
        }

        let persistence = await sessionManager.getPersistenceService()
        let contextManager = await sessionManager.getContextManager(for: id)

        // 1. Save Tool Outputs
        if let toolOutputs = chatRequest.toolOutputs {
            for output in toolOutputs {
                let msg = ConversationMessage(
                    sessionId: id,
                    role: .tool,
                    content: output.output,
                    toolCallId: output.toolCallId
                )
                try await persistence.saveMessage(msg)
            }
        }

        // 2. Save User Message
        if !chatRequest.message.isEmpty {
            let userMsg = ConversationMessage(
                sessionId: id, role: .user, content: chatRequest.message)
            try await persistence.saveMessage(userMsg)
        } else if chatRequest.toolOutputs?.isEmpty ?? true {
            throw HTTPError(.badRequest)
        }

        // 3. Fetch History & Context
        let history = try await sessionManager.getHistory(for: id)

        var contextData = ContextData()
        if let contextManager = contextManager {
            contextData = try await contextManager.gatherContext(
                for: chatRequest.message.isEmpty
                    ? (history.last?.content ?? "") : chatRequest.message,
                history: history,
                tagGenerator: { [llmService] query in try await llmService.generateTags(for: query)
                }
            )
        }

        guard await llmService.isConfigured else { throw HTTPError(.serviceUnavailable) }

        // 4. Resolve Tools
        var availableTools: [any MonadCore.Tool] = []
        if let toolRouter = toolRouter {
            do {
                var references = try await sessionManager.getAggregatedTools(for: id)

                // Include client tools if known
                if let clientId = chatRequest.clientId {
                    let clientTools = try await sessionManager.getClientTools(clientId: clientId)
                    references.append(contentsOf: clientTools)
                }

                // Deduplicate by ID
                var seenIds = Set<String>()
                references = references.filter { ref in
                    if seenIds.contains(ref.toolId) { return false }
                    seenIds.insert(ref.toolId)
                    return true
                }

                availableTools = references.compactMap {
                    (ref: ToolReference) -> (any MonadCore.Tool)? in
                    var def: WorkspaceToolDefinition?
                    switch ref {
                    case .known(let id): def = ServerToolRegistry.shared.getDefinition(for: id)
                    case .custom(let definition): def = definition
                    }
                    guard let d = def else { return nil }
                    return DelegatingTool(
                        ref: ref, router: toolRouter, sessionId: id, resolvedDefinition: d)
                        as any MonadCore.Tool
                }
            } catch {
                Logger.chat.warning("Failed to fetch tools: \(error)")
            }
        }

        let toolParams = availableTools.map { $0.toToolParam() }

        // Load Persona
        var systemInstructions: String? = nil
        if let personaFilename = session.persona, let workingDirectory = session.workingDirectory {
            let personaPath = URL(fileURLWithPath: workingDirectory).appendingPathComponent(
                "Personas"
            ).appendingPathComponent(personaFilename)
            if let content = try? String(contentsOf: personaPath, encoding: .utf8) {
                systemInstructions = content
            }
        }

        // 5. Build Initial Prompt
        let (initialMessages, _, structuredContext) = await llmService.buildPrompt(
            userQuery: chatRequest.message,
            contextNotes: contextData.notes,
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: availableTools,
            systemInstructions: systemInstructions
        )

        let modelName = await llmService.configuration.modelName

        // 6. Streaming Loop (ReAct)
        let sseStream = AsyncStream<ByteBuffer> { continuation in
            Task { [availableTools, initialMessages, toolParams, contextData, sessionManager, structuredContext, modelName] in
                var currentMessages = initialMessages
                var turnCount = 0
                let maxTurns = 5  // Safety limit

                // Debug accumulation
                var debugToolCalls: [ToolCallRecord] = []
                var debugToolResults: [ToolResultRecord] = []

                // A. Emit Metadata Event
                let metadata = ChatMetadata(
                    memories: contextData.memories.map { $0.memory.id },
                    files: contextData.notes.map { $0.name }
                )
                let metaDelta = ChatDelta(metadata: metadata)
                if let data = try? SerializationUtils.jsonEncoder.encode(metaDelta) {
                    let sseString = "data: \(String(decoding: data, as: UTF8.self))\n\n"
                    continuation.yield(ByteBuffer(string: sseString))
                }

                while turnCount < maxTurns {
                    turnCount += 1

                    do {
                        let streamData = await llmService.chatStream(
                            messages: currentMessages,
                            tools: toolParams.isEmpty ? nil : toolParams,
                            responseFormat: nil
                        )

                        var fullResponse = ""
                        var toolCallAccumulators: [Int: (id: String, name: String, args: String)] =
                            [:]

                        for try await result in streamData {
                            // Forward Content
                            if let delta = result.choices.first?.delta.content {
                                fullResponse += delta
                                let chatDelta = ChatDelta(content: delta)
                                if let data = try? SerializationUtils.jsonEncoder.encode(chatDelta)
                                {
                                    let sseString =
                                        "data: \(String(decoding: data, as: UTF8.self))\n\n"
                                    continuation.yield(ByteBuffer(string: sseString))
                                }
                            }

                            // Accumulate & Forward Tool Calls
                            if let calls = result.choices.first?.delta.toolCalls {
                                var toolDeltas: [ToolCallDelta] = []
                                for call in calls {
                                    guard let index = call.index else { continue }
                                    var acc = toolCallAccumulators[index] ?? ("", "", "")
                                    if let id = call.id { acc.id = id }
                                    if let name = call.function?.name { acc.name += name }
                                    if let args = call.function?.arguments { acc.args += args }
                                    toolCallAccumulators[index] = acc

                                    toolDeltas.append(
                                        ToolCallDelta(
                                            index: index,
                                            id: call.id,
                                            name: call.function?.name,
                                            arguments: call.function?.arguments
                                        ))
                                }

                                if !toolDeltas.isEmpty {
                                    let chatDelta = ChatDelta(toolCalls: toolDeltas)
                                    if let data = try? SerializationUtils.jsonEncoder.encode(
                                        chatDelta)
                                    {
                                        let sseString =
                                            "data: \(String(decoding: data, as: UTF8.self))\n\n"
                                        continuation.yield(ByteBuffer(string: sseString))
                                    }
                                }
                            }
                        }

                        // Process Turn Result
                        if !toolCallAccumulators.isEmpty {
                            let sortedCalls = toolCallAccumulators.sorted(by: { $0.key < $1.key })
                            let toolCallsParam:
                                [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam
                                    .ToolCallParam] = sortedCalls.map { _, value in
                                        .init(
                                            id: value.id,
                                            function: .init(arguments: value.args, name: value.name)
                                        )
                                    }

                            // Record tool calls for debug
                            for (_, value) in sortedCalls {
                                debugToolCalls.append(ToolCallRecord(
                                    name: value.name, arguments: value.args, turn: turnCount))
                            }

                            currentMessages.append(
                                .assistant(
                                    .init(
                                        content: .textContent(.init(fullResponse)),
                                        toolCalls: toolCallsParam)))

                            var executionResults: [ChatQuery.ChatCompletionMessageParam] = []
                            var requiresClientExecution = false

                            for call in toolCallsParam {
                                guard
                                    let tool = availableTools.first(where: {
                                        $0.name == call.function.name
                                    })
                                else {
                                    executionResults.append(
                                        .tool(
                                            .init(
                                                content: .textContent(
                                                    .init("Error: Tool not found")),
                                                toolCallId: call.id)))
                                    continue
                                }

                                let argsData = call.function.arguments.data(using: .utf8) ?? Data()
                                let argsDict =
                                    (try? JSONSerialization.jsonObject(with: argsData)
                                        as? [String: Any]) ?? [:]

                                do {
                                    let result = try await tool.execute(parameters: argsDict)
                                    debugToolResults.append(ToolResultRecord(
                                        toolCallId: call.id, name: call.function.name,
                                        output: result.output, turn: turnCount))
                                    executionResults.append(
                                        .tool(
                                            .init(
                                                content: .textContent(.init(result.output)),
                                                toolCallId: call.id)))
                                } catch let error as ToolError {
                                    if case .clientExecutionRequired = error {
                                        requiresClientExecution = true
                                        break
                                    }
                                    executionResults.append(
                                        .tool(
                                            .init(
                                                content: .textContent(
                                                    .init("Error: \(error.localizedDescription)")),
                                                toolCallId: call.id)))
                                } catch {
                                    executionResults.append(
                                        .tool(
                                            .init(
                                                content: .textContent(
                                                    .init("Error: \(error.localizedDescription)")),
                                                toolCallId: call.id)))
                                }
                            }

                            if requiresClientExecution {
                                let callsForDB = toolCallsParam.compactMap { param -> ToolCall? in
                                    let name = param.function.name
                                    let argsData =
                                        param.function.arguments.data(using: .utf8) ?? Data()
                                    let args =
                                        (try? JSONDecoder().decode(
                                            [String: AnyCodable].self, from: argsData)) ?? [:]
                                    return ToolCall(name: name, arguments: args)
                                }
                                let callsJSON =
                                    (try? SerializationUtils.jsonEncoder.encode(callsForDB)).flatMap
                                { String(decoding: $0, as: UTF8.self) } ?? "[]"

                                let assistantMsg = ConversationMessage(
                                    sessionId: id, role: .assistant, content: fullResponse,
                                    toolCalls: callsJSON)
                                try? await persistence.saveMessage(assistantMsg)

                                // Store debug snapshot
                                let snapshot = DebugSnapshot(
                                    structuredContext: structuredContext,
                                    toolCalls: debugToolCalls,
                                    toolResults: debugToolResults,
                                    model: modelName,
                                    turnCount: turnCount)
                                await sessionManager.setDebugSnapshot(snapshot, for: id)

                                let doneDelta = ChatDelta(isDone: true)
                                if let data = try? SerializationUtils.jsonEncoder.encode(doneDelta)
                                {
                                    continuation.yield(
                                        ByteBuffer(
                                            string:
                                                "data: \(String(decoding: data, as: UTF8.self))\n\n"
                                        ))
                                }
                                continuation.finish()
                                return
                            }

                            currentMessages.append(contentsOf: executionResults)
                            continue
                        } else {
                            // Final response
                            let assistantMsg = ConversationMessage(
                                sessionId: id,
                                role: .assistant,
                                content: fullResponse,
                                recalledMemories: String(
                                    decoding: (try? SerializationUtils.jsonEncoder.encode(
                                        contextData.memories.map { $0.memory })) ?? Data(),
                                    as: UTF8.self)
                            )
                            try? await persistence.saveMessage(assistantMsg)

                            // Store debug snapshot
                            let snapshot = DebugSnapshot(
                                structuredContext: structuredContext,
                                toolCalls: debugToolCalls,
                                toolResults: debugToolResults,
                                model: modelName,
                                turnCount: turnCount)
                            await sessionManager.setDebugSnapshot(snapshot, for: id)

                            let doneDelta = ChatDelta(isDone: true)
                            if let data = try? SerializationUtils.jsonEncoder.encode(doneDelta) {
                                continuation.yield(
                                    ByteBuffer(
                                        string: "data: \(String(decoding: data, as: UTF8.self))\n\n"
                                    ))
                            }
                            continuation.finish()
                            return
                        }
                    } catch {
                        Logger.chat.error("Stream error: \(error)")
                        let errorDelta = ChatDelta(error: error.localizedDescription)
                        if let data = try? SerializationUtils.jsonEncoder.encode(errorDelta) {
                            continuation.yield(
                                ByteBuffer(
                                    string: "data: \(String(decoding: data, as: UTF8.self))\n\n"))
                        }
                        continuation.finish()
                        return
                    }
                }
                continuation.finish()
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

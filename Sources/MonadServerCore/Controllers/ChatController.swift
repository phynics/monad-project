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
    }

    @Sendable func chat(_ request: Request, context: Context) async throws -> ChatResponse {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }

        let chatRequest = try await request.decode(as: ChatRequest.self, context: context)

        guard let session = await sessionManager.getSession(id: id) else {
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
            documents: [],
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

        guard let session = await sessionManager.getSession(id: id) else {
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
                let references = try await sessionManager.getAggregatedTools(for: id)
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
        let (initialMessages, _, _) = await llmService.buildPrompt(
            userQuery: chatRequest.message,
            contextNotes: contextData.notes,
            documents: [],
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: availableTools,
            systemInstructions: systemInstructions
        )

        // 6. Streaming Loop (ReAct)
        let sseStream = AsyncStream<ByteBuffer> { continuation in
            Task { [availableTools, initialMessages, toolParams, contextData] in
                var currentMessages = initialMessages
                var turnCount = 0
                let maxTurns = 5  // Safety limit

                while turnCount < maxTurns {
                    turnCount += 1

                    do {
                        let streamData = await llmService.chatStream(
                            messages: currentMessages,
                            tools: toolParams.isEmpty ? nil : toolParams,
                            responseFormat: nil
                        )

                        var fullResponse = ""
                        // Tuple to accumulate tool call parts
                        var toolCallAccumulators: [Int: (id: String, name: String, args: String)] =
                            [:]

                        for try await result in streamData {
                            // Forward Content
                            if let delta = result.choices.first?.delta.content {
                                fullResponse += delta
                                if let data = try? SerializationUtils.jsonEncoder.encode(result) {
                                    let sseString =
                                        "data: \(String(decoding: data, as: UTF8.self))\n\n"
                                    continuation.yield(ByteBuffer(string: sseString))
                                }
                            }

                            // Accumulate Tool Calls
                            if let calls = result.choices.first?.delta.toolCalls {
                                for call in calls {
                                    guard let index = call.index else { continue }
                                    var acc = toolCallAccumulators[index] ?? ("", "", "")
                                    if let id = call.id { acc.id = id }
                                    if let name = call.function?.name { acc.name += name }
                                    if let args = call.function?.arguments { acc.args += args }
                                    toolCallAccumulators[index] = acc

                                    // Forward tool call chunks to client
                                    if let data = try? SerializationUtils.jsonEncoder.encode(result)
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
                            // 1. Add Assistant Message with Tool Calls to history
                            let toolCallsParam:
                                [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam
                                    .ToolCallParam] = toolCallAccumulators.sorted(by: {
                                        $0.key < $1.key
                                    }).map { _, value in
                                        .init(
                                            id: value.id,
                                            function: .init(arguments: value.args, name: value.name)
                                        )
                                    }

                            currentMessages.append(
                                .assistant(
                                    .init(
                                        content: .textContent(.init(fullResponse)),
                                        toolCalls: toolCallsParam)))

                            // 2. Execute Tools
                            var executionResults: [ChatQuery.ChatCompletionMessageParam] = []
                            var requiresClientExecution = false

                            for call in toolCallsParam {
                                let function = call.function
                                guard
                                    let tool = availableTools.first(where: {
                                        $0.name == function.name
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

                                // Parse args
                                let argsData = function.arguments.data(using: .utf8) ?? Data()
                                let argsDict =
                                    (try? JSONSerialization.jsonObject(with: argsData)
                                        as? [String: Any]) ?? [:]

                                do {
                                    let result = try await tool.execute(parameters: argsDict)
                                    // Success (Local)
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
                                // Save Assistant Message
                                let callsForDB = toolCallsParam.compactMap { param -> ToolCall? in
                                    let name = param.function.name
                                    let argsStr = param.function.arguments
                                    guard let argsData = argsStr.data(using: .utf8)
                                    else { return nil }
                                    let args =
                                        (try? JSONDecoder().decode(
                                            [String: AnyCodable].self, from: argsData)) ?? [:]
                                    return ToolCall(name: name, arguments: args)
                                }
                                let callsJSON =
                                    (try? SerializationUtils.jsonEncoder.encode(callsForDB)).flatMap
                                { String(decoding: $0, as: UTF8.self) } ?? "[]"

                                let assistantMsg = ConversationMessage(
                                    sessionId: id,
                                    role: .assistant,
                                    content: fullResponse,
                                    toolCalls: callsJSON
                                )
                                try? await persistence.saveMessage(assistantMsg)

                                // End stream. Client has the calls.
                                continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
                                continuation.finish()
                                return
                            }

                            // Local execution done. Append results and Continue Loop.
                            currentMessages.append(contentsOf: executionResults)
                            continue

                        } else {
                            // No tool calls. Final response.
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

                            continuation.yield(ByteBuffer(string: "data: [DONE]\n\n"))
                            continuation.finish()
                            return
                        }

                    } catch {
                        Logger.chat.error("Stream error: \(error)")
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
}

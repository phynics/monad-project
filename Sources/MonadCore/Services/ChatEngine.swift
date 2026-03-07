import Dependencies
import Foundation
import Logging
import MonadPrompt
import MonadShared
import OpenAI

/// Unified chat engine that handles both interactive chat and autonomous agent execution.
/// Returns `AsyncThrowingStream<ChatEvent>` for all use cases — callers decide how to consume.
///
/// - Interactive chat (MonadServer): streams deltas to the client via SSE.
/// - Autonomous msAgents (MSAgentExecutor): consumes the stream internally for state tracking.
///
/// Tool resolution is the caller's responsibility. The engine accepts pre-resolved tools.
/// Timeline hydration is also the caller's responsibility for autonomous use cases.
public final class ChatEngine: @unchecked Sendable {
    @Dependency(\.timelineManager) private var timelineManager
    @Dependency(\.persistenceService) private var persistenceService
    @Dependency(\.llmService) private var llmService

    private let logger = Logger.module(named: "com.monad.chat-engine")

    public init() {}

    /// Execute a chat turn and return a stream of deltas.
    /// - Parameters:
    ///   - timelineId: The unique identifier for the chat session.
    ///   - message: The user's input message.
    ///   - tools: Pre-resolved tools available for this turn.
    ///   - toolOutputs: Optional list of tool outputs to be processed from a previous turn.
    ///   - contextManager: Optional context manager for RAG. If nil, no context is gathered.
    ///   - systemInstructions: Optional system instructions to override the default.
    ///   - maxTurns: Maximum number of LLM turns before stopping. Defaults to 5.
    /// - Returns: An asynchronous stream of chat events.
    public func chatStream(
        timelineId: UUID,
        message: String,
        tools: [AnyTool],
        toolOutputs: [ToolOutputSubmission]? = nil,
        contextManager: ContextManager? = nil,
        systemInstructions: String? = nil,
        agentInstanceId: UUID? = nil,
        maxTurns: Int = 5
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        let resolvedAgentId = agentInstanceId // capture for closure
        let sid = ANSIColors.colorize(timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
        logger.info("Starting chat stream for timeline \(sid)")

        // Save conversation steps (user message + any tool outputs from previous turn)
        try await saveConversationSteps(timelineId: timelineId, message: message, toolOutputs: toolOutputs)

        // Fetch history
        let history = try await timelineManager.getHistory(for: timelineId)

        // Gather context (RAG)
        let contextData = await fetchContext(contextManager: contextManager, message: message, history: history)

        guard await llmService.isConfigured else { throw ToolError.executionFailed("LLM Service not configured") }

        let toolParams = tools.map { $0.toToolParam() }

        // Build prompt
        let timeline = await timelineManager.getTimeline(id: timelineId)
        let workspaces = await timelineManager.getWorkspaces(for: timelineId)
        let attachedWorkspaces = workspaces?.attached ?? []

        var clientName: String?
        let connectedClients = Set<UUID>()

        // Find which workspaces are connected
        if let primaryWorkspace = workspaces?.primary {
            if let ownerId = primaryWorkspace.ownerId {
                // Try to get client
                if let client = try? await persistenceService.fetchClient(id: ownerId) {
                    clientName = client.displayName
                }
            }
        }

        let (initialMessages, structuredContext) = await buildPrompt(
            timeline: timeline,
            message: message,
            contextData: contextData,
            history: history,
            availableTools: tools,
            workspaces: attachedWorkspaces,
            primaryWorkspace: workspaces?.primary,
            clientName: clientName,
            connectedClients: connectedClients,
            systemInstructions: systemInstructions
        )

        let modelName = await llmService.configuration.modelName

        return AsyncThrowingStream<ChatEvent, Error> { continuation in
            let task = Task {
                await self.runChatLoop(
                    continuation: continuation,
                    timelineId: timelineId,
                    initialMessages: initialMessages,
                    toolParams: toolParams,
                    availableTools: tools,
                    contextData: contextData,
                    structuredContext: structuredContext,
                    modelName: modelName,
                    agentInstanceId: resolvedAgentId,
                    maxTurns: maxTurns
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Core Loop

    private enum TurnResult {
        case `continue`(newMessages: [ChatQuery.ChatCompletionMessageParam])
        case finish
    }

    private func runChatLoop(
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        timelineId: UUID,
        initialMessages: [ChatQuery.ChatCompletionMessageParam],
        toolParams: [ChatQuery.ChatCompletionToolParam],
        availableTools: [AnyTool],
        contextData: ContextData,
        structuredContext: [String: String],
        modelName: String,
        agentInstanceId: UUID?,
        maxTurns: Int
    ) async {
        var currentMessages = initialMessages
        var turnCount = 0
        var accumulatedRawOutput = ""

        // Emit Metadata Event
        let metadata = ChatMetadata(
            memories: contextData.memories.map { $0.memory.id },
            files: contextData.notes.map { $0.name }
        )
        continuation.yield(.generationContext(metadata))

        while turnCount < maxTurns {
            turnCount += 1
            let sid = ANSIColors.colorize(timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
            let turnStr = ANSIColors.colorize("\(turnCount)", color: ANSIColors.brightYellow)
            logger.info("Starting turn \(turnStr) for timeline \(sid)")

            if Task.isCancelled {
                continuation.yield(.error(CancellationError()))
                continuation.finish()
                return
            }

            do {
                let result = try await processTurn(
                    currentMessages: currentMessages,
                    toolParams: toolParams,
                    availableTools: availableTools,
                    contextData: contextData,
                    structuredContext: structuredContext,
                    modelName: modelName,
                    turnCount: turnCount,
                    timelineId: timelineId,
                    agentInstanceId: agentInstanceId,
                    continuation: continuation,
                    accumulatedRawOutput: &accumulatedRawOutput
                )

                switch result {
                case let .continue(newMessages):
                    currentMessages.append(contentsOf: newMessages)
                case .finish:
                    continuation.finish()
                    return
                }
            } catch {
                if error is CancellationError {
                    continuation.finish(throwing: error)
                } else {
                    logger.error("Error in chat loop turn \(turnCount): \(error)")
                    continuation.finish(throwing: error)
                }
                return
            }
        }

        // If we hit maxTurns, we still yield a completion event for the last turn's state
        // but without a new message (since we didn't get a final text response).
        continuation.yield(.generationCompleted(
            message: Message(timestamp: Date(), content: "", role: .assistant, isSummary: true),
            metadata: APIResponseMetadata(model: modelName, duration: 0, tokensPerSecond: 0)
        ))

        continuation.finish()
    }

    private func processTurn(
        currentMessages: [ChatQuery.ChatCompletionMessageParam],
        toolParams: [ChatQuery.ChatCompletionToolParam],
        availableTools: [AnyTool],
        contextData: ContextData,
        structuredContext: [String: String],
        modelName: String,
        turnCount: Int,
        timelineId: UUID,
        agentInstanceId: UUID?,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        accumulatedRawOutput: inout String
    ) async throws -> TurnResult {
        let authorId = agentInstanceId // stamp on assistant messages
        var debugToolCalls: [ToolCallRecord] = []
        var debugToolResults: [ToolResultRecord] = []

        let streamData = await llmService.chatStream(
            messages: currentMessages,
            tools: toolParams.isEmpty ? nil : toolParams,
            responseFormat: nil
        )

        var fullResponse = ""
        var fullThinking = ""
        var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]

        var parser = StreamingParser()

        // Bug 1: Track timing and token usage
        let turnStartTime = Date()
        var streamUsage: ChatResult.CompletionUsage?

        for try await result in streamData {
            if Task.isCancelled { break }

            // Capture usage stats (sent in final chunk when includeUsage: true)
            if let usage = result.usage { streamUsage = usage }

            // Forward Content and Thinking
            if let delta = result.choices.first?.delta.content {
                let oldThinkingCount = parser.thinking.count
                let oldContentCount = parser.content.count

                parser.process(delta)

                let thinkingChunk: Substring
                let contentChunk: Substring

                if parser.hasReclassified {
                    thinkingChunk = parser.thinking.dropFirst(oldThinkingCount)
                    contentChunk = ""
                } else {
                    thinkingChunk = parser.thinking.dropFirst(oldThinkingCount)
                    contentChunk = parser.content.dropFirst(oldContentCount)
                }

                if !thinkingChunk.isEmpty {
                    fullThinking += thinkingChunk
                    continuation.yield(.thinking(String(thinkingChunk)))
                }

                if !contentChunk.isEmpty {
                    fullResponse += contentChunk
                    continuation.yield(.generation(String(contentChunk)))
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

                    continuation.yield(.toolCall(ToolCallDelta(
                        index: index,
                        id: call.id,
                        name: call.function?.name,
                        arguments: call.function?.arguments
                    )))
                }
            }
        }

        // Flush Any Pending Text
        if !parser.buffer.isEmpty {
            if parser.isThinking {
                fullThinking += parser.buffer
                continuation.yield(.thinking(parser.buffer))
            } else {
                fullResponse += parser.buffer
                continuation.yield(.generation(parser.buffer))
            }
        }

        // Accumulate raw output for debug
        accumulatedRawOutput += fullThinking
        accumulatedRawOutput += fullResponse

        let renderedPrompt = renderMessages(currentMessages)

        if Task.isCancelled { throw CancellationError() }

        var finalToolCalls = toolCallAccumulators

        // Parse fallback calls if needed
        if finalToolCalls.isEmpty {
            let fallbackCalls = ToolOutputParser.parse(from: fullResponse)
            if !fallbackCalls.isEmpty {
                logger.warning("Structured tool calls empty — falling back to text parsing. Parsed \(fallbackCalls.count) call(s) from response text.")
                for (index, call) in fallbackCalls.enumerated() {
                    let argsJson = (try? SerializationUtils.jsonEncoder.encode(call.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    finalToolCalls[index] = (id: UUID().uuidString, name: call.name, args: argsJson)
                }

                for (index, value) in finalToolCalls.sorted(by: { $0.key < $1.key }) {
                    continuation.yield(.toolCall(ToolCallDelta(index: index, id: value.id, name: value.name, arguments: value.args)))
                }
            } else if fullResponse.contains("tool_call") || fullResponse.contains("\"name\"") {
                logger.warning("No structured tool calls and fallback parser found nothing, but response contains tool-like text. Response prefix: \(String(fullResponse.prefix(200)))")
            }
        }

        // Filter out sentinel tool call names. Some models emit artifacts like
        // name="tool_call" as a formatting token.
        let validToolCalls = finalToolCalls.filter { _, value in
            !value.name.isEmpty && value.name != "tool_call"
        }

        finalToolCalls = validToolCalls

        // Bug 1: Compute timing and token metadata after the stream loop
        let turnDuration = Date().timeIntervalSince(turnStartTime)
        let completionTokens = streamUsage?.completionTokens
            ?? TokenEstimator.estimate(text: fullResponse + fullThinking)
        let tokensPerSecond: Double? = turnDuration > 0
            ? Double(completionTokens) / turnDuration : nil

        if !finalToolCalls.isEmpty {
            let sortedCalls = finalToolCalls.sorted(by: { $0.key < $1.key })
            let toolCallsParam: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] = sortedCalls.map { _, value in
                .init(id: value.id, function: .init(arguments: value.args, name: value.name))
            }

            for (_, value) in sortedCalls {
                debugToolCalls.append(ToolCallRecord(name: value.name, arguments: value.args, turn: turnCount))
            }

            let assistantMessage = ChatQuery.ChatCompletionMessageParam.assistant(.init(content: .textContent(.init(fullResponse)), toolCalls: toolCallsParam))

            let (executionResults, requiresClientExecution, newDebugRecords) = await executeTools(
                calls: toolCallsParam,
                availableTools: availableTools,
                turnCount: turnCount,
                continuation: continuation
            )
            debugToolResults.append(contentsOf: newDebugRecords)

            if requiresClientExecution {
                let callsForDB = toolCallsParam.compactMap { param -> ToolCall? in
                    let argsData = param.function.arguments.data(using: .utf8) ?? Data()
                    let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
                    return ToolCall(name: param.function.name, arguments: args)
                }
                let callsJSON = (try? SerializationUtils.jsonEncoder.encode(callsForDB)).flatMap { String(decoding: $0, as: UTF8.self) } ?? "[]"

                let assistantMsg = ConversationMessage(timelineId: timelineId, role: .assistant, content: fullResponse, think: fullThinking.isEmpty ? nil : fullThinking, toolCalls: callsJSON, agentInstanceId: authorId)
                do {
                    try await persistenceService.saveMessage(assistantMsg)
                } catch {
                    logger.error("Failed to save assistant message: \(error)")
                }

                let snapshot = DebugSnapshot(structuredContext: structuredContext, toolCalls: debugToolCalls, toolResults: debugToolResults, model: modelName, turnCount: turnCount)
                await timelineManager.setDebugSnapshot(snapshot, for: timelineId)

                let snapshotData = try? SerializationUtils.jsonEncoder.encode(snapshot)
                continuation.yield(.generationCompleted(
                    message: assistantMsg.toMessage(),
                    metadata: APIResponseMetadata(
                        model: modelName,
                        promptTokens: streamUsage?.promptTokens,
                        completionTokens: streamUsage?.completionTokens,
                        totalTokens: streamUsage?.totalTokens,
                        duration: turnDuration,
                        tokensPerSecond: tokensPerSecond,
                        debugSnapshotData: snapshotData
                    )
                ))
                return .finish
            }

            var newMessages: [ChatQuery.ChatCompletionMessageParam] = [assistantMessage]
            newMessages.append(contentsOf: executionResults)
            return .continue(newMessages: newMessages)

        } else {
            let assistantMsg = ConversationMessage(
                timelineId: timelineId,
                role: .assistant,
                content: fullResponse,
                recalledMemories: String(decoding: (try? SerializationUtils.jsonEncoder.encode(contextData.memories.map { $0.memory })) ?? Data(), as: UTF8.self),
                think: fullThinking.isEmpty ? nil : fullThinking,
                agentInstanceId: authorId
            )
            do {
                try await persistenceService.saveMessage(assistantMsg)
            } catch {
                logger.error("Failed to save assistant message: \(error)")
            }

            let snapshot = DebugSnapshot(
                structuredContext: structuredContext,
                toolCalls: debugToolCalls,
                toolResults: debugToolResults,
                renderedPrompt: renderedPrompt,
                rawOutput: accumulatedRawOutput,
                model: modelName,
                turnCount: turnCount
            )
            await timelineManager.setDebugSnapshot(snapshot, for: timelineId)

            let snapshotData = try? SerializationUtils.jsonEncoder.encode(snapshot)
            continuation.yield(.generationCompleted(
                message: assistantMsg.toMessage(),
                metadata: APIResponseMetadata(
                    model: modelName,
                    promptTokens: streamUsage?.promptTokens,
                    completionTokens: streamUsage?.completionTokens,
                    totalTokens: streamUsage?.totalTokens,
                    duration: turnDuration,
                    tokensPerSecond: tokensPerSecond,
                    debugSnapshotData: snapshotData
                )
            ))
            return .finish
        }
    }

    // MARK: - Helper Methods

    private func saveConversationSteps(
        timelineId: UUID,
        message: String,
        toolOutputs: [ToolOutputSubmission]?
    ) async throws {
        if let toolOutputs = toolOutputs {
            for output in toolOutputs {
                let msg = ConversationMessage(
                    timelineId: timelineId,
                    role: .tool,
                    content: output.output,
                    toolCallId: output.toolCallId
                )
                try await persistenceService.saveMessage(msg)
            }
        }

        if !message.isEmpty {
            let userMsg = ConversationMessage(timelineId: timelineId, role: .user, content: message)
            try await persistenceService.saveMessage(userMsg)
        } else if toolOutputs?.isEmpty ?? true {
            throw ToolError.invalidArgument("input", expected: "message or toolOutputs", got: "empty")
        }
    }

    private func fetchContext(
        contextManager: ContextManager?,
        message: String,
        history: [Message]
    ) async -> ContextData {
        guard let contextManager = contextManager else { return ContextData() }

        do {
            let stream = await contextManager.gatherContext(
                for: message.isEmpty ? (history.last?.content ?? "") : message,
                history: history,
                tagGenerator: { [llmService] query in try await llmService.generateTags(for: query) }
            )

            for try await event in stream {
                if case let .complete(data) = event {
                    return data
                }
            }
        } catch {
            logger.warning("Failed to gather context: \(error)")
        }
        return ContextData()
    }

    private func buildPrompt(
        timeline _: Timeline?,
        message: String,
        contextData: ContextData,
        history: [Message],
        availableTools: [AnyTool],
        workspaces: [WorkspaceReference],
        primaryWorkspace: WorkspaceReference?,
        clientName: String?,
        connectedClients: Set<UUID>,
        systemInstructions: String?
    ) async -> (messages: [ChatQuery.ChatCompletionMessageParam], structuredContext: [String: String]) {
        let prompt = await llmService.buildContext(
            userQuery: message,
            contextNotes: contextData.notes,
            memories: contextData.memories.map { $0.memory },
            chatHistory: history,
            tools: availableTools,
            workspaces: workspaces,
            primaryWorkspace: primaryWorkspace,
            clientName: clientName,
            connectedClients: connectedClients,
            systemInstructions: systemInstructions
        )

        // Convert to OpenAI format
        let messages = await prompt.toMessages()
        let structuredContext = await prompt.structuredContext()

        return (messages, structuredContext)
    }

    private func executeTools(
        calls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam],
        availableTools: [AnyTool],
        turnCount: Int,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async -> (results: [ChatQuery.ChatCompletionMessageParam], requiresClientExecution: Bool, debugRecords: [ToolResultRecord]) {
        var executionResults: [ChatQuery.ChatCompletionMessageParam] = []
        var requiresClientExecution = false
        var debugRecords: [ToolResultRecord] = []

        for call in calls {
            let toolName = ANSIColors.colorize(call.function.name, color: ANSIColors.brightCyan)
            guard let tool = availableTools.first(where: { $0.id == call.function.name }) else {
                logger.error("Tool not found: \(toolName)")
                executionResults.append(.tool(.init(content: .textContent(.init("Error: Tool not found")), toolCallId: call.id)))
                continuation.yield(.toolCallError(toolCallId: call.id, name: call.function.name, error: "Tool not found: \(call.function.name)"))
                continue
            }

            // Bug 2: Emit attempting event so the CLI can show tool progress
            let toolRef = tool.toolReference
            continuation.yield(.toolProgress(toolCallId: call.id, status: .attempting(name: tool.name, reference: toolRef)))

            let argsData = call.function.arguments.data(using: .utf8) ?? Data()
            let argsDict = (try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]) ?? [:]

            logger.info("Executing tool \(toolName)...")
            do {
                let result = try await tool.execute(parameters: argsDict)
                debugRecords.append(ToolResultRecord(toolCallId: call.id, name: call.function.name, output: result.output, turn: turnCount))
                if result.success {
                    logger.info("Tool \(toolName) succeeded")
                    continuation.yield(.toolCompleted(toolCallId: call.id, status: .success(result)))
                } else {
                    let errorMsg = result.error ?? "Unknown error"
                    logger.error("Tool \(toolName) failed: \(errorMsg)")
                    continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: errorMsg)))
                }
                executionResults.append(.tool(.init(content: .textContent(.init(result.output)), toolCallId: call.id)))
            } catch let error as ToolError {
                if case .clientExecutionRequired = error {
                    logger.info("Tool \(toolName) requires client execution")
                    requiresClientExecution = true
                    break
                }
                logger.error("Tool \(toolName) error: \(error.localizedDescription)")
                executionResults.append(.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)))
                continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: error.localizedDescription)))
            } catch {
                logger.error("Tool \(toolName) unexpected error: \(error.localizedDescription)")
                executionResults.append(.tool(.init(content: .textContent(.init("Error: \(error.localizedDescription)")), toolCallId: call.id)))
                continuation.yield(.toolCompleted(toolCallId: call.id, status: .failed(reference: toolRef, error: error.localizedDescription)))
            }
        }
        return (executionResults, requiresClientExecution, debugRecords)
    }

    private func renderMessages(_ messages: [ChatQuery.ChatCompletionMessageParam]) -> String {
        var output = ""
        for message in messages {
            switch message {
            case let .system(param):
                output += "─── [SYSTEM] ───\n\(param.content)\n\n"
            case let .user(param):
                output += "─── [USER] ───\n\(param.content)\n\n"
            case let .assistant(param):
                var content = ""
                if let contentValue = param.content {
                    content = "\(contentValue)"
                }
                output += "─── [ASSISTANT] ───\n\(content)\n"
                if let toolCalls = param.toolCalls {
                    for call in toolCalls {
                        output += "Call: \(call.function.name)(\(call.function.arguments))\n"
                    }
                }
                output += "\n"
            case let .tool(param):
                output += "─── [TOOL: \(param.toolCallId)] ───\n\(param.content)\n\n"
            case let .developer(param):
                output += "─── [DEVELOPER] ───\n\(param.content)\n\n"
            @unknown default:
                output += "─── [UNKNOWN] ───\n\(message)\n\n"
            }
        }
        return output
    }
}

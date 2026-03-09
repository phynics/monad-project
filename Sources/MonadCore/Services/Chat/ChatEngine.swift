import Dependencies
import Foundation
import Logging
import MonadPrompt
import MonadShared
import OpenAI

/// Unified chat engine that handles both interactive chat and autonomous agent execution.
/// Returns `AsyncThrowingStream<ChatEvent>` for all use cases — callers decide how to consume.
///
/// The engine orchestrates the entire lifecycle of a chat turn, including context gathering,
/// LLM interaction, tool execution, and state persistence.
public final class ChatEngine: @unchecked Sendable {
    // MARK: - Constants

    public enum Constants {
        public static let maxHistoryTokens = 120_000
        public static let historyTokenBuffer = 4000
        public static let sentinelToolName = "tool_call"
        public static let defaultMaxTurns = 5
    }

    @Dependency(\.timelineManager) var timelineManager
    @Dependency(\.agentInstanceStore) var agentInstanceStore
    @Dependency(\.clientStore) var clientStore
    @Dependency(\.messageStore) var messageStore
    @Dependency(\.llmService) var llmService
    @Dependency(\.toolRouter) var toolRouter

    let logger = Logger.module(named: "com.monad.chat-engine")

    public init() {}

    // MARK: - Public API

    /// Execute a chat turn and return a stream of deltas.
    /// - Parameters:
    ///   - timelineId: The unique identifier for the chat session.
    ///   - message: The user's input message.
    ///   - tools: Pre-resolved tools available for this turn.
    ///   - toolOutputs: Optional list of tool outputs submitted by the client from a previous turn.
    ///   - contextManager: Optional context manager for RAG. If nil, no context is gathered.
    ///   - systemInstructions: Optional system instructions to override the default.
    ///   - agentInstanceId: Optional identifier for the agent instance.
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
        maxTurns: Int = Constants.defaultMaxTurns
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        let resolvedAgentId = agentInstanceId // capture for closure
        let sid = ANSIColors.colorize(timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
        logger.info("Starting chat stream for timeline \(sid)")

        // Save conversation steps (user message + any tool outputs submitted by client)
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

        // Fetch attached agent instance for identity context
        let agentInstance: AgentInstance? = resolvedAgentId != nil
            ? try? await agentInstanceStore.fetchAgentInstance(id: resolvedAgentId!)
            : nil

        var clientName: String?
        let connectedClients = Set<UUID>()

        // Find which workspaces are connected
        if let primaryWorkspace = workspaces?.primary {
            if let ownerId = primaryWorkspace.ownerId {
                if let client = try? await clientStore.fetchClient(id: ownerId) {
                    clientName = client.displayName
                }
            }
        }

        let (initialMessages, structuredContext) = await buildPrompt(
            timeline: timeline,
            agentInstance: agentInstance,
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
                continuation.yield(.generationCancelled())
                continuation.finish()
                return
            }

            let context: ChatTurnContext
            do {
                context = try await processTurn(
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
            } catch {
                if error is CancellationError {
                    continuation.finish(throwing: error)
                } else {
                    logger.error("Error in chat loop turn \(turnCount): \(error)")
                    continuation.finish(throwing: error)
                }
                return
            }

            // No tool calls → generation is complete for this turn.
            guard !context.toolCallAccumulators.isEmpty else {
                continuation.finish()
                return
            }

            // Build ParsedToolCall list from the validated accumulators.
            let sortedCalls = context.toolCallAccumulators.sorted(by: { $0.key < $1.key })
            let parsedCalls = sortedCalls.map { _, value in
                ParsedToolCall(callId: value.id, name: value.name, argumentsJSON: value.args)
            }

            // Build the assistant LLM message for in-memory context continuation.
            let toolCallsParam = sortedCalls.map { _, value in
                ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
                    id: value.id,
                    function: .init(arguments: value.args, name: value.name)
                )
            }
            let assistantParam = ChatQuery.ChatCompletionMessageParam.assistant(
                .init(content: .textContent(.init(context.fullResponse)), toolCalls: toolCallsParam)
            )

            do {
                let result = try await toolRouter.handlePendingToolCalls(
                    timelineId: timelineId,
                    calls: parsedCalls,
                    availableTools: availableTools,
                    continuation: continuation
                )

                if result.hasDeferred {
                    // Client tools are pending. Stream ends; client will loop back with results.
                    continuation.finish()
                    return
                }

                // All tools resolved server-side — continue the loop with updated message history.
                var newMessages: [ChatQuery.ChatCompletionMessageParam] = [assistantParam]
                newMessages.append(contentsOf: result.resolvedToolParams)
                currentMessages.append(contentsOf: newMessages)

            } catch {
                logger.error("Tool execution error on turn \(turnCount): \(error)")
                continuation.finish(throwing: error)
                return
            }
        }

        // Max turns reached.
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
    ) async throws -> ChatTurnContext {
        var context = ChatTurnContext(
            timelineId: timelineId,
            agentInstanceId: agentInstanceId,
            modelName: modelName,
            turnCount: turnCount,
            currentMessages: currentMessages,
            toolParams: toolParams,
            availableTools: availableTools,
            contextData: contextData,
            structuredContext: structuredContext,
            continuation: continuation,
            accumulatedRawOutput: accumulatedRawOutput
        )

        let pipeline = Pipeline<ChatTurnContext>()
            .add(LLMStreamingStage(llmService: llmService, logger: logger))
            .add(ToolExecutionStage(logger: logger))
            .add(PersistenceStage(messageStore: messageStore, timelineManager: timelineManager, logger: logger))

        try await pipeline.execute(&context)

        accumulatedRawOutput = context.accumulatedRawOutput
        return context
    }

    // MARK: - Utilities

    static func renderMessagesStatic(_ messages: [ChatQuery.ChatCompletionMessageParam]) -> String {
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

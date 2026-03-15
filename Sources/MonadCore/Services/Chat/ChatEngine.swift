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
    @Dependency(\.chatTurnPlugins) var chatTurnPlugins

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
    public func execute(
        timelineId: UUID,
        message: String,
        tools: [AnyTool],
        toolOutputs: [ToolOutputSubmission]? = nil,
        contextManager: ContextManager? = nil,
        systemInstructions: String? = nil,
        agentInstanceId: UUID? = nil,
        maxTurns: Int = Constants.defaultMaxTurns
    ) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        let sid = ANSIColors.colorize(timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
        logger.info("Starting chat stream for timeline \(sid)")

        guard await llmService.isConfigured else { throw ChatEngineError.llmServiceNotConfigured }

        try await saveConversationSteps(timelineId: timelineId, message: message, toolOutputs: toolOutputs)

        let history = try await timelineManager.getHistory(for: timelineId)
        let contextData = await fetchContext(contextManager: contextManager, message: message, history: history)

        let workspaceResult = await timelineManager.getWorkspaces(for: timelineId)
        let entities = await resolveEntities(
            timelineId: timelineId,
            agentInstanceId: agentInstanceId,
            primaryWorkspaceOwnerId: workspaceResult?.primary?.ownerId
        )

        let params = BuildPromptParams(
            timelineId: timelineId,
            timeline: entities.timeline,
            agentInstance: entities.agentInstance,
            message: message,
            contextData: contextData,
            history: history,
            availableTools: tools,
            workspaces: workspaceResult?.attached ?? [],
            primaryWorkspace: workspaceResult?.primary,
            clientName: entities.clientName,
            systemInstructions: systemInstructions
        )
        let (initialMessages, structuredContext) = await buildPrompt(params)
        let modelName = await llmService.configuration.modelName

        let context = ChatTurnContext(
            timelineId: timelineId,
            agentInstanceId: agentInstanceId,
            modelName: modelName,
            maxTurns: maxTurns,
            systemInstructions: systemInstructions,
            availableTools: tools,
            contextData: contextData,
            structuredContext: structuredContext,
            currentMessages: initialMessages,
            turnCount: 0,
            outputs: TurnOutputs()
        )

        return AsyncThrowingStream<ChatEvent, Error> { continuation in
            let task = Task {
                await self.runChatLoop(continuation: continuation, context: context)
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Core Loop

    private enum LoopContinuation {
        case stop
        case continueWith([ChatQuery.ChatCompletionMessageParam])
    }

    /// The heart of the agentic loop. Orchestrates multiple turns until the agent finishes
    /// or reaches the max turn limit.
    private func runChatLoop(
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        context: ChatTurnContext
    ) async {
        // 1. Emit initial RAG context for frontend observability
        continuation.yield(.generationContext(ChatMetadata(
            memories: context.contextData.memories.map { $0.memory.id },
            files: context.contextData.notes.map { $0.name }
        )))

        var loopMessages = context.currentMessages
        var turnCount = 0
        var priorOutput = ""

        // 2. Main reasoning loop (ReAct loop)
        while turnCount < context.maxTurns {
            turnCount += 1
            let turnContext = context.forTurn(
                turnCount: turnCount,
                messages: loopMessages,
                priorAccumulatedOutput: priorOutput
            )

            // Execute one turn (LLM call + automatic server-side tool routing)
            let signal = await runOneTurn(continuation: continuation, context: turnContext)
            priorOutput = await turnContext.outputs.accumulatedRawOutput

            switch signal {
            case .stop:
                // Turn finished without further internal actions required
                var pluginMessages: [ChatQuery.ChatCompletionMessageParam] = []
                let completedTurn = CompletedTurn(
                    timelineId: context.timelineId,
                    agentInstanceId: context.agentInstanceId,
                    turnCount: turnCount,
                    fullResponse: priorOutput,
                    modelName: context.modelName
                )

                // 3. Post-turn plugin execution (e.g. autonomous reactions, background jobs)
                do {
                    for plugin in chatTurnPlugins {
                        pluginMessages += try await plugin.afterTurn(completedTurn)
                    }
                } catch {
                    logger.error("Plugin error after turn \(turnCount): \(error)")
                    continuation.finish(throwing: error)
                    return
                }

                // If plugins added context, resume the loop for a follow-up turn
                if !pluginMessages.isEmpty, turnCount < context.maxTurns {
                    loopMessages += pluginMessages
                } else {
                    continuation.finish()
                    return
                }

            case let .continueWith(newMessages):
                // A tool result or internal thought needs the LLM to process it in the next turn
                loopMessages += newMessages
            }
        }

        logger.warning("Max turns (\(context.maxTurns)) reached for timeline \(context.timelineId)")
        continuation.finish()
    }

    private func runOneTurn(
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        context: ChatTurnContext
    ) async -> LoopContinuation {
        let sid = ANSIColors.colorize(
            context.timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue
        )
        let turnLabel = ANSIColors.colorize("\(context.turnCount)", color: ANSIColors.brightYellow)
        logger.info("Starting turn \(turnLabel) for timeline \(sid)")

        if Task.isCancelled {
            continuation.yield(.generationCancelled())
            continuation.finish()
            return .stop
        }

        do {
            try await processTurn(context: context, continuation: continuation)
        } catch is CancellationError {
            continuation.yield(.generationCancelled())
            continuation.finish()
            return .stop
        } catch {
            logger.error("Error in chat loop turn \(context.turnCount): \(error)")
            continuation.finish(throwing: error)
            return .stop
        }

        do {
            return try await handleToolCallsAfterTurn(context: context, continuation: continuation)
        } catch {
            logger.error("Tool execution error on turn \(context.turnCount): \(error)")
            continuation.finish(throwing: error)
            return .stop
        }
    }

    /// Inspects the outputs of the previous turn and handles any requested tool calls.
    ///
    /// - If tools can be resolved on the server, they are executed immediately and the results
    ///   are returned so the loop can continue (multi-step reasoning).
    /// - If any tool requires client-side execution, the turn stops and defers to the client.
    private func handleToolCallsAfterTurn(
        context: ChatTurnContext,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws -> LoopContinuation {
        // 1. Extract and parse streamed tool calls from the turn outputs
        let accumulators = await context.outputs.toolCallAccumulators
        guard !accumulators.isEmpty else { return .stop }

        let sortedCalls = accumulators.sorted(by: { $0.key < $1.key })
        let parsedCalls = sortedCalls.map { _, value in
            ParsedToolCall(callId: value.callId, name: value.name, argumentsJSON: value.args)
        }

        // 2. Prepare the assistant's message (including the tool_calls definition)
        // This is necessary to maintain valid conversation history for the next turn.
        let toolCallsParam = sortedCalls.map { _, value in
            ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
                id: value.callId, function: .init(arguments: value.args, name: value.name)
            )
        }
        let fullResponse = await context.outputs.fullResponse
        let assistantParam = ChatQuery.ChatCompletionMessageParam.assistant(
            .init(content: .textContent(.init(fullResponse)), toolCalls: toolCallsParam)
        )

        // 3. Route calls to the ToolRouter
        // This executes server-side tools immediately and emits progress/completion events.
        let result = try await toolRouter.handlePendingToolCalls(
            timelineId: context.timelineId,
            calls: parsedCalls,
            availableTools: context.availableTools,
            continuation: continuation
        )

        // 4. Decision: Can we keep going autonomously?
        // If any tool was deferred to the client, we MUST stop and wait for a response.
        if result.hasDeferred { return .stop }

        // If all tools were resolved locally, we continue the turn automatically with results added to history.
        return .continueWith([assistantParam] + result.resolvedToolParams)
    }

    private func processTurn(
        context: ChatTurnContext,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        let pipeline = Pipeline<ChatTurnContext, ChatEvent>()
            .add(LLMStreamingStage(llmService: llmService, logger: logger))
            .add(ToolCallExtractionStage(logger: logger))
            .add(MessagePersistenceStage(messageStore: messageStore, logger: logger))

        let stream = pipeline.execute(context)
        for try await event in stream {
            continuation.yield(event)
        }
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

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

    // MARK: - Configuration

    /// Bundles the per-loop invariants that are fixed for the entire multi-turn generation.
    struct ChatLoopConfig {
        let timelineId: UUID
        let toolParams: [ChatQuery.ChatCompletionToolParam]
        let availableTools: [AnyTool]
        let contextData: ContextData
        let structuredContext: [String: String]
        let modelName: String
        let agentInstanceId: UUID?
        let maxTurns: Int
    }

    /// Input bundle for `buildLoopConfig`, grouping session-scoped chat parameters.
    struct LoopConfigInput {
        let message: String
        let tools: [AnyTool]
        let contextData: ContextData
        let history: [Message]
        let agentInstanceId: UUID?
        let maxTurns: Int
        let systemInstructions: String?
    }

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
        let sid = ANSIColors.colorize(timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue)
        logger.info("Starting chat stream for timeline \(sid)")

        try await saveConversationSteps(timelineId: timelineId, message: message, toolOutputs: toolOutputs)

        let history = try await timelineManager.getHistory(for: timelineId)
        let contextData = await fetchContext(contextManager: contextManager, message: message, history: history)

        guard await llmService.isConfigured else { throw ToolError.executionFailed("LLM Service not configured") }

        let input = LoopConfigInput(
            message: message, tools: tools, contextData: contextData, history: history,
            agentInstanceId: agentInstanceId, maxTurns: maxTurns, systemInstructions: systemInstructions
        )
        let config = try await buildLoopConfig(timelineId: timelineId, input: input)

        return AsyncThrowingStream<ChatEvent, Error> { continuation in
            let task = Task {
                await self.runChatLoop(
                    continuation: continuation,
                    initialMessages: config.0,
                    config: config.1
                )
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Core Loop

    private enum LoopContinuation: Equatable {
        case `continue`
        case stop
    }

    private enum PostTurnAction {
        case finish
        case continueWith([ChatQuery.ChatCompletionMessageParam])
    }

    private func runChatLoop(
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        initialMessages: [ChatQuery.ChatCompletionMessageParam],
        config: ChatLoopConfig
    ) async {
        var currentMessages = initialMessages
        var turnCount = 0
        var accumulatedRawOutput = ""

        continuation.yield(.generationContext(ChatMetadata(
            memories: config.contextData.memories.map { $0.memory.id },
            files: config.contextData.notes.map { $0.name }
        )))

        while turnCount < config.maxTurns {
            turnCount += 1
            let signal = await runOneTurn(
                continuation: continuation,
                messages: &currentMessages,
                turnCount: turnCount,
                config: config,
                rawOutput: &accumulatedRawOutput
            )
            if signal == .stop { return }
        }

        continuation.yield(.generationCompleted(
            message: Message(timestamp: Date(), content: "", role: .assistant, isSummary: true),
            metadata: APIResponseMetadata(model: config.modelName, duration: 0, tokensPerSecond: 0)
        ))
        continuation.finish()
    }

    private func runOneTurn(
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        messages: inout [ChatQuery.ChatCompletionMessageParam],
        turnCount: Int,
        config: ChatLoopConfig,
        rawOutput: inout String
    ) async -> LoopContinuation {
        let sid = ANSIColors.colorize(
            config.timelineId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightBlue
        )
        let turnLabel = ANSIColors.colorize("\(turnCount)", color: ANSIColors.brightYellow)
        logger.info("Starting turn \(turnLabel) for timeline \(sid)")

        if Task.isCancelled {
            continuation.yield(.generationCancelled())
            continuation.finish()
            return .stop
        }

        let context: ChatTurnContext
        do {
            context = try await processTurn(
                currentMessages: messages,
                turnCount: turnCount,
                config: config,
                continuation: continuation,
                accumulatedRawOutput: &rawOutput
            )
        } catch {
            if !(error is CancellationError) {
                logger.error("Error in chat loop turn \(turnCount): \(error)")
            }
            continuation.finish(throwing: error)
            return .stop
        }

        let action: PostTurnAction
        do {
            action = try await handleToolCallsAfterTurn(
                context: context, config: config, continuation: continuation
            )
        } catch {
            logger.error("Tool execution error on turn \(turnCount): \(error)")
            continuation.finish(throwing: error)
            return .stop
        }

        switch action {
        case .finish:
            continuation.finish()
            return .stop
        case let .continueWith(newMessages):
            messages.append(contentsOf: newMessages)
            return .continue
        }
    }

    private func handleToolCallsAfterTurn(
        context: ChatTurnContext,
        config: ChatLoopConfig,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws -> PostTurnAction {
        guard !context.toolCallAccumulators.isEmpty else { return .finish }

        let sortedCalls = context.toolCallAccumulators.sorted(by: { $0.key < $1.key })
        let parsedCalls = sortedCalls.map { _, value in
            ParsedToolCall(callId: value.id, name: value.name, argumentsJSON: value.args)
        }
        let toolCallsParam = sortedCalls.map { _, value in
            ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam(
                id: value.id, function: .init(arguments: value.args, name: value.name)
            )
        }
        let assistantParam = ChatQuery.ChatCompletionMessageParam.assistant(
            .init(content: .textContent(.init(context.fullResponse)), toolCalls: toolCallsParam)
        )
        let result = try await toolRouter.handlePendingToolCalls(
            timelineId: config.timelineId,
            calls: parsedCalls,
            availableTools: config.availableTools,
            continuation: continuation
        )
        if result.hasDeferred { return .finish }
        return .continueWith([assistantParam] + result.resolvedToolParams)
    }

    private func processTurn(
        currentMessages: [ChatQuery.ChatCompletionMessageParam],
        turnCount: Int,
        config: ChatLoopConfig,
        continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation,
        accumulatedRawOutput: inout String
    ) async throws -> ChatTurnContext {
        var context = ChatTurnContext(
            timelineId: config.timelineId,
            agentInstanceId: config.agentInstanceId,
            modelName: config.modelName,
            turnCount: turnCount,
            currentMessages: currentMessages,
            toolParams: config.toolParams,
            availableTools: config.availableTools,
            contextData: config.contextData,
            structuredContext: config.structuredContext,
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

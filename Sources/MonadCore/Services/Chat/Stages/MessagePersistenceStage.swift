import Foundation
import Logging
import MonadShared
import OpenAI

/// Pipeline stage responsible for persisting the assistant message and emitting the completion event.
///
/// Always saves the assistant message produced by the LLM turn:
/// - With `toolCalls` JSON when the LLM requested tool calls (pending execution).
/// - Without `toolCalls` when the response is a plain text reply.
///
/// After this stage, `ChatEngine.runChatLoop` inspects `context.outputs.toolCallAccumulators` to decide
/// whether to invoke `ToolRouter.handlePendingToolCalls` and continue the loop.
struct MessagePersistenceStage: PipelineStage {
    let messageStore: any MessageStoreProtocol
    let logger: Logger

    func process(_ context: ChatTurnContext) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        let hasPendingToolCalls = await !context.outputs.toolCallAccumulators.isEmpty
        let toolCallsJSON = await buildToolCallsJSON(from: context, hasPendingToolCalls: hasPendingToolCalls)
        let recalledMemories = buildRecalledMemories(from: context, hasPendingToolCalls: hasPendingToolCalls)

        let fullResponse = await context.outputs.fullResponse
        let fullThinking = await context.outputs.fullThinking
        let streamUsage = await context.outputs.streamUsage
        let turnDuration = await context.outputs.turnDuration
        let tokensPerSecond = await context.outputs.tokensPerSecond

        let assistantMsg = ConversationMessage(
            timelineId: context.timelineId,
            role: .assistant,
            content: fullResponse,
            recalledMemories: recalledMemories,
            think: fullThinking.isEmpty ? nil : fullThinking,
            toolCalls: toolCallsJSON,
            agentInstanceId: context.agentInstanceId
        )
        try await messageStore.saveMessage(assistantMsg)

        let snapshot = await buildDebugSnapshot(from: context, hasPendingToolCalls: hasPendingToolCalls)
        let snapshotData = try? SerializationUtils.jsonEncoder.encode(snapshot)

        return AsyncThrowingStream { continuation in
            if !hasPendingToolCalls {
                continuation.yield(.generationCompleted(
                    message: assistantMsg.toMessage(),
                    metadata: APIResponseMetadata(
                        model: context.modelName,
                        promptTokens: streamUsage?.promptTokens,
                        completionTokens: streamUsage?.completionTokens,
                        totalTokens: streamUsage?.totalTokens,
                        duration: turnDuration,
                        tokensPerSecond: tokensPerSecond,
                        debugSnapshotData: snapshotData
                    )
                ))
            }
            continuation.finish()
        }
    }

    private func buildToolCallsJSON(from context: ChatTurnContext, hasPendingToolCalls: Bool) async -> String {
        guard hasPendingToolCalls else { return "[]" }
        let sortedCalls = await context.outputs.toolCallAccumulators.sorted(by: { $0.key < $1.key })
        let callsForDB = sortedCalls.compactMap { _, value -> ToolCall? in
            let argsData = value.args.data(using: .utf8) ?? Data()
            let args = (try? SerializationUtils.jsonDecoder.decode([String: AnyCodable].self, from: argsData)) ?? [:]
            return ToolCall(name: value.name, arguments: args)
        }
        return (try? SerializationUtils.jsonEncoder.encode(callsForDB))
            .flatMap { String(bytes: $0, encoding: .utf8) } ?? "[]"
    }

    private func buildRecalledMemories(from context: ChatTurnContext, hasPendingToolCalls: Bool) -> String {
        guard !hasPendingToolCalls else { return "[]" }
        let memories = context.contextData.memories.map { $0.memory }
        return (try? SerializationUtils.jsonEncoder.encode(memories))
            .flatMap { String(bytes: $0, encoding: .utf8) } ?? "[]"
    }

    private func buildDebugSnapshot(from context: ChatTurnContext, hasPendingToolCalls _: Bool) async -> DebugSnapshot {
        let debugToolCalls = await context.outputs.debugToolCalls
        let debugToolResults = await context.outputs.debugToolResults
        let accumulatedRawOutput = await context.outputs.accumulatedRawOutput
        return DebugSnapshot(
            structuredContext: context.structuredContext,
            toolCalls: debugToolCalls,
            toolResults: debugToolResults,
            renderedPrompt: ChatEngine.renderMessagesStatic(context.currentMessages),
            rawOutput: accumulatedRawOutput,
            model: context.modelName,
            turnCount: context.turnCount
        )
    }
}

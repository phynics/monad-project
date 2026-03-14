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
        let hasPendingToolCalls = !context.outputs.toolCallAccumulators.isEmpty
        let toolCallsJSON = buildToolCallsJSON(from: context, hasPendingToolCalls: hasPendingToolCalls)
        let recalledMemories = buildRecalledMemories(from: context, hasPendingToolCalls: hasPendingToolCalls)

        let assistantMsg = ConversationMessage(
            timelineId: context.timelineId,
            role: .assistant,
            content: context.outputs.fullResponse,
            recalledMemories: recalledMemories,
            think: context.outputs.fullThinking.isEmpty ? nil : context.outputs.fullThinking,
            toolCalls: toolCallsJSON,
            agentInstanceId: context.agentInstanceId
        )
        try await messageStore.saveMessage(assistantMsg)

        let snapshot = buildDebugSnapshot(from: context, hasPendingToolCalls: hasPendingToolCalls)
        let snapshotData = try? SerializationUtils.jsonEncoder.encode(snapshot)

        return AsyncThrowingStream { continuation in
            if !hasPendingToolCalls {
                continuation.yield(.generationCompleted(
                    message: assistantMsg.toMessage(),
                    metadata: APIResponseMetadata(
                        model: context.modelName,
                        promptTokens: context.outputs.streamUsage?.promptTokens,
                        completionTokens: context.outputs.streamUsage?.completionTokens,
                        totalTokens: context.outputs.streamUsage?.totalTokens,
                        duration: context.outputs.turnDuration,
                        tokensPerSecond: context.outputs.tokensPerSecond,
                        debugSnapshotData: snapshotData
                    )
                ))
            }
            continuation.finish()
        }
    }

    private func buildToolCallsJSON(from context: ChatTurnContext, hasPendingToolCalls: Bool) -> String {
        guard hasPendingToolCalls else { return "[]" }
        let sortedCalls = context.outputs.toolCallAccumulators.sorted(by: { $0.key < $1.key })
        let callsForDB = sortedCalls.compactMap { _, value -> ToolCall? in
            let argsData = value.args.data(using: .utf8) ?? Data()
            let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
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

    private func buildDebugSnapshot(from context: ChatTurnContext, hasPendingToolCalls _: Bool) -> DebugSnapshot {
        DebugSnapshot(
            structuredContext: context.structuredContext,
            toolCalls: context.outputs.debugToolCalls,
            toolResults: context.outputs.debugToolResults,
            renderedPrompt: ChatEngine.renderMessagesStatic(context.currentMessages),
            rawOutput: context.outputs.accumulatedRawOutput,
            model: context.modelName,
            turnCount: context.turnCount
        )
    }
}

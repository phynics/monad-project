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

        let fullResponse = await context.outputs.fullResponse
        let fullThinking = await context.outputs.fullThinking
        let streamUsage = await context.outputs.streamUsage
        let turnDuration = await context.outputs.turnDuration
        let tokensPerSecond = await context.outputs.tokensPerSecond

        let recalledMemories: String
        if hasPendingToolCalls {
            recalledMemories = "[]"
        } else {
            let memories = context.contextData.memories.map { $0.memory }
            recalledMemories = (try? SerializationUtils.jsonEncoder.encode(memories))
                .flatMap { String(bytes: $0, encoding: .utf8) } ?? "[]"
        }

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

        let snapshot = await buildTurnSnapshot(from: context)
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
                        turnSnapshotData: snapshotData
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

    private func buildTurnSnapshot(from context: ChatTurnContext) async -> TurnSnapshot {
        let debugToolCalls = await context.outputs.debugToolCalls
        let debugToolResults = await context.outputs.debugToolResults
        let accumulatedRawOutput = await context.outputs.accumulatedRawOutput
        let fullResponse = await context.outputs.fullResponse
        let fullThinking = await context.outputs.fullThinking
        let turnDuration = await context.outputs.turnDuration
        let tokensPerSecond = await context.outputs.tokensPerSecond
        let streamUsage = await context.outputs.streamUsage

        return TurnSnapshot(
            timelineId: context.timelineId,
            agentInstanceId: context.agentInstanceId,
            modelName: context.modelName,
            turnCount: context.turnCount,
            maxTurns: context.maxTurns,
            systemInstructions: context.systemInstructions,
            availableToolIds: context.availableTools.map { $0.id },
            renderedPrompt: ChatEngine.renderMessagesStatic(context.currentMessages),
            fullResponse: fullResponse,
            fullThinking: fullThinking,
            rawOutput: accumulatedRawOutput,
            toolCalls: debugToolCalls,
            toolResults: debugToolResults,
            turnDuration: turnDuration,
            tokensPerSecond: tokensPerSecond,
            promptTokens: streamUsage?.promptTokens,
            completionTokens: streamUsage?.completionTokens,
            totalTokens: streamUsage?.totalTokens
        )
    }
}

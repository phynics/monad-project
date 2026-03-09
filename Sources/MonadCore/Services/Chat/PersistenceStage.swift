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
/// After this stage, `ChatEngine.runChatLoop` inspects `context.toolCallAccumulators` to decide
/// whether to invoke `ToolRouter.handlePendingToolCalls` and continue the loop.
struct PersistenceStage: PipelineStage {
    let messageStore: any MessageStoreProtocol
    let timelineManager: TimelineManager
    let logger: Logger

    func process(_ context: inout ChatTurnContext) async throws {
        let authorId = context.agentInstanceId
        let hasPendingToolCalls = !context.toolCallAccumulators.isEmpty

        // Build tool calls JSON for the DB when the LLM requested tools.
        let toolCallsJSON: String
        if hasPendingToolCalls {
            let sortedCalls = context.toolCallAccumulators.sorted(by: { $0.key < $1.key })
            let callsForDB = sortedCalls.compactMap { _, value -> ToolCall? in
                let argsData = value.args.data(using: .utf8) ?? Data()
                let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
                return ToolCall(name: value.name, arguments: args)
            }
            toolCallsJSON =
                (try? SerializationUtils.jsonEncoder.encode(callsForDB))
                    .flatMap { String(decoding: $0, as: UTF8.self) } ?? "[]"
        } else {
            toolCallsJSON = "[]"
        }

        // Recalled memories are only relevant on final (non-tool-call) responses.
        let recalledMemories: String
        if hasPendingToolCalls {
            recalledMemories = "[]"
        } else {
            recalledMemories = String(
                decoding: (try? SerializationUtils.jsonEncoder.encode(context.contextData.memories.map { $0.memory })) ?? Data(),
                as: UTF8.self
            )
        }

        let assistantMsg = ConversationMessage(
            timelineId: context.timelineId,
            role: .assistant,
            content: context.fullResponse,
            recalledMemories: recalledMemories,
            think: context.fullThinking.isEmpty ? nil : context.fullThinking,
            toolCalls: toolCallsJSON,
            agentInstanceId: authorId
        )
        try await messageStore.saveMessage(assistantMsg)

        // Debug snapshot — include rendered prompt/raw output only on final responses.
        let snapshot = DebugSnapshot(
            structuredContext: context.structuredContext,
            toolCalls: context.debugToolCalls,
            toolResults: context.debugToolResults,
            renderedPrompt: hasPendingToolCalls ? nil : ChatEngine.renderMessagesStatic(context.currentMessages),
            rawOutput: hasPendingToolCalls ? nil : context.accumulatedRawOutput,
            model: context.modelName,
            turnCount: context.turnCount
        )
        await timelineManager.setDebugSnapshot(snapshot, for: context.timelineId)

        let snapshotData = try? SerializationUtils.jsonEncoder.encode(snapshot)
        context.continuation.yield(.generationCompleted(
            message: assistantMsg.toMessage(),
            metadata: APIResponseMetadata(
                model: context.modelName,
                promptTokens: context.streamUsage?.promptTokens,
                completionTokens: context.streamUsage?.completionTokens,
                totalTokens: context.streamUsage?.totalTokens,
                duration: context.turnDuration,
                tokensPerSecond: context.tokensPerSecond,
                debugSnapshotData: snapshotData
            )
        ))

        context.turnResult = .finish
    }
}

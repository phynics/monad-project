import Foundation
import Logging
import MonadShared
import OpenAI

/// Pipeline stage responsible for persisting the final turn state and yielding completion events.
struct PersistenceStage: PipelineStage {
    let persistenceService: any FullPersistenceService
    let timelineManager: TimelineManager
    let logger: Logger

    func process(_ context: inout ChatTurnContext) async throws {
        let authorId = context.agentInstanceId

        if context.requiresClientExecution {
            // Parse tool calls for DB
            let sortedCalls = context.toolCallAccumulators.sorted(by: { $0.key < $1.key })
            let toolCallsParam: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] = sortedCalls.map { _, value in
                .init(id: value.id, function: .init(arguments: value.args, name: value.name))
            }

            let callsForDB = toolCallsParam.compactMap { param -> ToolCall? in
                let argsData = param.function.arguments.data(using: .utf8) ?? Data()
                let args = (try? JSONDecoder().decode([String: AnyCodable].self, from: argsData)) ?? [:]
                return ToolCall(name: param.function.name, arguments: args)
            }
            let callsJSON = (try? SerializationUtils.jsonEncoder.encode(callsForDB)).flatMap { String(decoding: $0, as: UTF8.self) } ?? "[]"

            let assistantMsg = ConversationMessage(timelineId: context.timelineId, role: .assistant, content: context.fullResponse, think: context.fullThinking.isEmpty ? nil : context.fullThinking, toolCalls: callsJSON, agentInstanceId: authorId)
            try await persistenceService.saveMessage(assistantMsg)

            let snapshot = DebugSnapshot(structuredContext: context.structuredContext, toolCalls: context.debugToolCalls, toolResults: context.debugToolResults, model: context.modelName, turnCount: context.turnCount)
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
        } else if case .finish = context.turnResult {
            let assistantMsg = ConversationMessage(
                timelineId: context.timelineId,
                role: .assistant,
                content: context.fullResponse,
                recalledMemories: String(decoding: (try? SerializationUtils.jsonEncoder.encode(context.contextData.memories.map { $0.memory })) ?? Data(), as: UTF8.self),
                think: context.fullThinking.isEmpty ? nil : context.fullThinking,
                agentInstanceId: authorId
            )
            try await persistenceService.saveMessage(assistantMsg)

            let renderedPrompt = ChatEngine.renderMessagesStatic(context.currentMessages)
            let snapshot = DebugSnapshot(
                structuredContext: context.structuredContext,
                toolCalls: context.debugToolCalls,
                toolResults: context.debugToolResults,
                renderedPrompt: renderedPrompt,
                rawOutput: context.accumulatedRawOutput,
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
        }
    }
}

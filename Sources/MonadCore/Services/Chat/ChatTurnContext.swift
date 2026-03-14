import Foundation
import MonadShared
import OpenAI

// SAFETY: Pipeline stages execute sequentially (each stage completes before the next begins).
// No concurrent mutation of var fields occurs, making @unchecked Sendable correct here.
final class TurnOutputs: @unchecked Sendable {
    var fullResponse: String = ""
    var fullThinking: String = ""
    var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]
    var streamUsage: ChatResult.CompletionUsage?
    var turnDuration: TimeInterval = 0
    var tokensPerSecond: Double?
    var accumulatedRawOutput: String
    var debugToolCalls: [ToolCallRecord] = []
    var debugToolResults: [ToolResultRecord] = []

    init(priorAccumulatedOutput: String = "") {
        accumulatedRawOutput = priorAccumulatedOutput
    }
}

/// Immutable snapshot of a single chat turn as it moves through the pipeline.
/// Mutable stage outputs are stored in `outputs`, a shared class reference.
struct ChatTurnContext: Sendable {
    // Session-level fields — identical across all turns in a generation.
    let timelineId: UUID
    let agentInstanceId: UUID?
    let modelName: String
    let maxTurns: Int
    let systemInstructions: String?
    let availableTools: [AnyTool]
    let contextData: ContextData
    let structuredContext: [String: String]

    // Per-turn snapshot — different each iteration.
    let currentMessages: [ChatQuery.ChatCompletionMessageParam]
    let turnCount: Int

    /// Tool parameters derived from availableTools — not stored redundantly.
    var toolParams: [ChatQuery.ChatCompletionToolParam] {
        availableTools.map { $0.toToolParam() }
    }

    /// Mutable stage outputs shared via class reference across struct copies.
    let outputs: TurnOutputs

    /// Creates a new per-turn context from this session template.
    func forTurn(
        turnCount: Int,
        messages: [ChatQuery.ChatCompletionMessageParam],
        priorAccumulatedOutput: String
    ) -> ChatTurnContext {
        ChatTurnContext(
            timelineId: timelineId,
            agentInstanceId: agentInstanceId,
            modelName: modelName,
            maxTurns: maxTurns,
            systemInstructions: systemInstructions,
            availableTools: availableTools,
            contextData: contextData,
            structuredContext: structuredContext,
            currentMessages: messages,
            turnCount: turnCount,
            outputs: TurnOutputs(priorAccumulatedOutput: priorAccumulatedOutput)
        )
    }
}

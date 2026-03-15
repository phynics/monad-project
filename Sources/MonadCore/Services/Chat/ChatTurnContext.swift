import Foundation
import MonadShared
import OpenAI

/// Accumulates parts of a streamed tool call.
struct StreamedToolCall: Sendable {
    var callId: String
    var name: String
    var args: String

    init(callId: String = "", name: String = "", args: String = "") {
        self.callId = callId
        self.name = name
        self.args = args
    }
}

/// Actor-isolated mutable outputs for a single pipeline turn.
/// Each stage writes into this via dedicated mutation methods; reads from outside use `await`.
actor TurnOutputs {
    private(set) var fullResponse: String = ""
    private(set) var fullThinking: String = ""
    private(set) var toolCallAccumulators: [Int: StreamedToolCall] = [:]
    private(set) var streamUsage: ChatResult.CompletionUsage?
    private(set) var turnDuration: TimeInterval = 0
    private(set) var tokensPerSecond: Double?
    private(set) var accumulatedRawOutput: String
    private(set) var debugToolCalls: [ToolCallRecord] = []
    private(set) var debugToolResults: [ToolResultRecord] = []

    init(priorAccumulatedOutput: String = "") {
        accumulatedRawOutput = priorAccumulatedOutput
    }

    // MARK: - Mutation Methods

    func setStreamUsage(_ usage: ChatResult.CompletionUsage) {
        streamUsage = usage
    }

    func appendThinking(_ chunk: String) {
        fullThinking += chunk
    }

    func appendResponse(_ chunk: String) {
        fullResponse += chunk
    }

    func accumulateToolCall(index: Int, id: String?, name: String?, args: String?) {
        var acc = toolCallAccumulators[index] ?? StreamedToolCall()
        if let id { acc.callId = id }
        if let name { acc.name += name }
        if let args { acc.args += args }
        toolCallAccumulators[index] = acc
    }

    func setToolCallAccumulator(index: Int, id: String, name: String, args: String) {
        toolCallAccumulators[index] = StreamedToolCall(callId: id, name: name, args: args)
    }

    func removeSentinelAndEmptyToolCalls(sentinel: String) {
        toolCallAccumulators = toolCallAccumulators.filter { _, value in
            !value.name.isEmpty && value.name != sentinel
        }
    }

    func addDebugToolCall(_ record: ToolCallRecord) {
        debugToolCalls.append(record)
    }

    func addDebugToolResult(_ record: ToolResultRecord) {
        debugToolResults.append(record)
    }

    /// Finalizes the turn: accumulates raw output and computes timing/throughput metrics.
    func finalizeTurn(startTime: Date) {
        accumulatedRawOutput += fullThinking
        accumulatedRawOutput += fullResponse
        turnDuration = Date().timeIntervalSince(startTime)
        let completionTokens = streamUsage?.completionTokens
            ?? TokenEstimator.estimate(text: fullResponse + fullThinking)
        tokensPerSecond = turnDuration > 0 ? Double(completionTokens) / turnDuration : nil
    }
}

/// Immutable snapshot of a single chat turn as it moves through the pipeline.
/// Mutable stage outputs are stored in `outputs`, a shared actor reference.
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

    /// Mutable stage outputs shared via actor reference across struct copies.
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

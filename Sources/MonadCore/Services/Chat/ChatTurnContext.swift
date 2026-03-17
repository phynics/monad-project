import Foundation
import MonadShared
import OpenAI

/// Accumulates parts of a streamed tool call.
public struct StreamedToolCall: Sendable {
    public var callId: String
    public var name: String
    public var args: String

    public init(callId: String = "", name: String = "", args: String = "") {
        self.callId = callId
        self.name = name
        self.args = args
    }
}

/// Actor-isolated mutable outputs for a single pipeline turn.
/// Each stage writes into this via dedicated mutation methods; reads from outside use `await`.
public actor TurnOutputs {
    public private(set) var fullResponse: String = ""
    public private(set) var fullThinking: String = ""
    public private(set) var toolCallAccumulators: [Int: StreamedToolCall] = [:]
    public private(set) var streamUsage: ChatResult.CompletionUsage?
    public private(set) var turnDuration: TimeInterval = 0
    public private(set) var tokensPerSecond: Double?
    public private(set) var debugToolCalls: [ToolCallRecord] = []
    public private(set) var debugToolResults: [ToolResultRecord] = []

    public init() {}

    // MARK: - Mutation Methods

    public func setStreamUsage(_ usage: ChatResult.CompletionUsage) {
        streamUsage = usage
    }

    public func appendThinking(_ chunk: String) {
        fullThinking += chunk
    }

    public func appendResponse(_ chunk: String) {
        fullResponse += chunk
    }

    public func accumulateToolCall(index: Int, id: String?, name: String?, args: String?) {
        var acc = toolCallAccumulators[index] ?? StreamedToolCall()
        if let id { acc.callId = id }
        if let name { acc.name += name }
        if let args { acc.args += args }
        toolCallAccumulators[index] = acc
    }

    public func setToolCallAccumulator(index: Int, id: String, name: String, args: String) {
        toolCallAccumulators[index] = StreamedToolCall(callId: id, name: name, args: args)
    }

    public func removeSentinelAndEmptyToolCalls(sentinel: String) {
        toolCallAccumulators = toolCallAccumulators.filter { _, value in
            !value.name.isEmpty && value.name != sentinel
        }
    }

    public func addDebugToolCall(_ record: ToolCallRecord) {
        debugToolCalls.append(record)
    }

    public func addDebugToolResult(_ record: ToolResultRecord) {
        debugToolResults.append(record)
    }

    /// Finalizes the turn: computes timing and throughput metrics.
    public func finalizeTurn(startTime: Date) {
        turnDuration = Date().timeIntervalSince(startTime)
        let completionTokens = streamUsage?.completionTokens
            ?? TokenEstimator.estimate(text: fullResponse + fullThinking)
        tokensPerSecond = turnDuration > 0 ? Double(completionTokens) / turnDuration : nil
    }
}

/// Immutable snapshot of a single chat turn as it moves through the pipeline.
/// Mutable stage outputs are stored in `outputs`, a shared actor reference.
public struct ChatTurnContext: Sendable {
    // Session-level configuration (constant across turns)
    public let timelineId: UUID
    public let agentInstanceId: UUID?
    public let modelName: String
    public let maxTurns: Int
    public let systemInstructions: String?
    public let availableTools: [AnyTool]
    public let contextData: ContextData
    public let remoteDepth: Int

    // Per-turn snapshot (changes each iteration)
    public let currentMessages: [ChatQuery.ChatCompletionMessageParam]
    public let turnCount: Int

    /// Mutable stage outputs shared via actor reference across struct copies.
    public let outputs: TurnOutputs
    
    public init(
        timelineId: UUID,
        agentInstanceId: UUID?,
        modelName: String,
        maxTurns: Int,
        systemInstructions: String?,
        availableTools: [AnyTool],
        contextData: ContextData,
        remoteDepth: Int,
        currentMessages: [ChatQuery.ChatCompletionMessageParam],
        turnCount: Int,
        outputs: TurnOutputs = TurnOutputs()
    ) {
        self.timelineId = timelineId
        self.agentInstanceId = agentInstanceId
        self.modelName = modelName
        self.maxTurns = maxTurns
        self.systemInstructions = systemInstructions
        self.availableTools = availableTools
        self.contextData = contextData
        self.remoteDepth = remoteDepth
        self.currentMessages = currentMessages
        self.turnCount = turnCount
        self.outputs = outputs
    }

    /// Tool parameters derived from availableTools.
    public var toolParams: [ChatQuery.ChatCompletionToolParam] {
        availableTools.map { $0.toToolParam() }
    }

    /// Creates a new snapshot for the next turn while keeping the same session config.
    public func forTurn(
        turnCount: Int,
        messages: [ChatQuery.ChatCompletionMessageParam]
    ) -> ChatTurnContext {
        ChatTurnContext(
            timelineId: timelineId,
            agentInstanceId: agentInstanceId,
            modelName: modelName,
            maxTurns: maxTurns,
            systemInstructions: systemInstructions,
            availableTools: availableTools,
            contextData: contextData,
            remoteDepth: remoteDepth,
            currentMessages: messages,
            turnCount: turnCount,
            outputs: TurnOutputs()
        )
    }
}
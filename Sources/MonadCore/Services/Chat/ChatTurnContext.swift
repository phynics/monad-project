import Foundation
import MonadShared
import OpenAI

/// Internal state container for a single chat turn as it moves through the pipeline.
final class ChatTurnContext: @unchecked Sendable {
    let timelineId: UUID
    let agentInstanceId: UUID?
    let modelName: String
    let turnCount: Int
    let currentMessages: [ChatQuery.ChatCompletionMessageParam]
    let toolParams: [ChatQuery.ChatCompletionToolParam]
    let availableTools: [AnyTool]
    let contextData: ContextData
    let structuredContext: [String: String]

    // Output from stages
    var fullResponse: String = ""
    var fullThinking: String = ""
    var toolCallAccumulators: [Int: (id: String, name: String, args: String)] = [:]
    var streamUsage: ChatResult.CompletionUsage?
    var turnDuration: TimeInterval = 0
    var tokensPerSecond: Double?
    var accumulatedRawOutput: String = ""

    var debugToolCalls: [ToolCallRecord] = []
    var debugToolResults: [ToolResultRecord] = []

    init(
        timelineId: UUID,
        agentInstanceId: UUID?,
        modelName: String,
        turnCount: Int,
        currentMessages: [ChatQuery.ChatCompletionMessageParam],
        toolParams: [ChatQuery.ChatCompletionToolParam],
        availableTools: [AnyTool],
        contextData: ContextData,
        structuredContext: [String: String],
        accumulatedRawOutput: String
    ) {
        self.timelineId = timelineId
        self.agentInstanceId = agentInstanceId
        self.modelName = modelName
        self.turnCount = turnCount
        self.currentMessages = currentMessages
        self.toolParams = toolParams
        self.availableTools = availableTools
        self.contextData = contextData
        self.structuredContext = structuredContext
        self.accumulatedRawOutput = accumulatedRawOutput
    }
}

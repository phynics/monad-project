import Foundation
import MonadShared
import OpenAI

/// Internal state container for a single chat turn as it moves through the pipeline.
struct ChatTurnContext {
    let timelineId: UUID
    let agentInstanceId: UUID?
    let modelName: String
    let turnCount: Int
    let currentMessages: [ChatQuery.ChatCompletionMessageParam]
    let toolParams: [ChatQuery.ChatCompletionToolParam]
    let availableTools: [AnyTool]
    let contextData: ContextData
    let structuredContext: [String: String]
    let continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation

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

    var turnResult: TurnResult = .finish
    var requiresClientExecution: Bool = false
}

enum TurnResult {
    case `continue`(newMessages: [ChatQuery.ChatCompletionMessageParam])
    case finish
}

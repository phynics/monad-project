import Foundation
import Logging
import MonadShared
import OpenAI

/// Pipeline stage responsible for extracting and executing tool calls from the LLM response.
struct ToolExecutionStage: PipelineStage {
    typealias ToolExecutor = @Sendable (
        _ calls: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam],
        _ availableTools: [AnyTool],
        _ turnCount: Int,
        _ continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async -> (
        results: [ChatQuery.ChatCompletionMessageParam],
        requiresClientExecution: Bool,
        debugRecords: [ToolResultRecord]
    )

    let executeTools: ToolExecutor
    let logger: Logger

    func process(_ context: inout ChatTurnContext) async throws {
        var finalToolCalls = context.toolCallAccumulators

        if finalToolCalls.isEmpty {
            let fallbackCalls = ToolOutputParser.parse(from: context.fullResponse)
            if !fallbackCalls.isEmpty {
                logger.warning("Structured tool calls empty — falling back to text parsing. Parsed \(fallbackCalls.count) call(s) from response text.")
                for (index, call) in fallbackCalls.enumerated() {
                    let argsJson = (try? SerializationUtils.jsonEncoder.encode(call.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    finalToolCalls[index] = (id: UUID().uuidString, name: call.name, args: argsJson)
                }

                for (index, value) in finalToolCalls.sorted(by: { $0.key < $1.key }) {
                    context.continuation.yield(.toolCall(ToolCallDelta(index: index, id: value.id, name: value.name, arguments: value.args)))
                }
            }
        }

        let validToolCalls = finalToolCalls.filter { _, value in
            !value.name.isEmpty && value.name != ChatEngine.Constants.sentinelToolName
        }

        if !validToolCalls.isEmpty {
            let sortedCalls = validToolCalls.sorted(by: { $0.key < $1.key })
            let toolCallsParam: [ChatQuery.ChatCompletionMessageParam.AssistantMessageParam.ToolCallParam] = sortedCalls.map { _, value in
                .init(id: value.id, function: .init(arguments: value.args, name: value.name))
            }

            for (_, value) in sortedCalls {
                context.debugToolCalls.append(ToolCallRecord(name: value.name, arguments: value.args, turn: context.turnCount))
            }

            let assistantMessage = ChatQuery.ChatCompletionMessageParam.assistant(.init(content: .textContent(.init(context.fullResponse)), toolCalls: toolCallsParam))

            let (executionResults, requiresClientExecution, newDebugRecords) = await executeTools(
                toolCallsParam,
                context.availableTools,
                context.turnCount,
                context.continuation
            )
            context.debugToolResults.append(contentsOf: newDebugRecords)
            context.requiresClientExecution = requiresClientExecution

            if !requiresClientExecution {
                var newMessages: [ChatQuery.ChatCompletionMessageParam] = [assistantMessage]
                newMessages.append(contentsOf: executionResults)
                context.turnResult = .continue(newMessages: newMessages)
            }
        } else {
            context.turnResult = .finish
        }
    }
}

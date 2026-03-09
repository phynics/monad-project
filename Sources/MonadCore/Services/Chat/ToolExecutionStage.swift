import Foundation
import Logging
import MonadShared
import OpenAI

/// Pipeline stage responsible for extracting and normalising tool calls from the LLM response.
///
/// This stage does NOT execute tools. It validates and cleans `context.toolCallAccumulators`
/// so that `PersistenceStage` and `ChatEngine.runChatLoop` can rely on it:
/// - Falls back to text parsing when the LLM didn't emit structured tool calls.
/// - Strips sentinel and empty-named calls.
/// - Appends records for the debug snapshot.
///
/// Actual execution is handled by `ToolRouter.handlePendingToolCalls()`, called from
/// `ChatEngine.runChatLoop` after the pipeline completes.
struct ToolExecutionStage: PipelineStage {
    let logger: Logger

    func process(_ context: inout ChatTurnContext) async throws {
        // Fallback: parse tool calls from response text when structured calls are absent.
        if context.toolCallAccumulators.isEmpty {
            let fallbackCalls = ToolOutputParser.parse(from: context.fullResponse)
            if !fallbackCalls.isEmpty {
                logger.warning(
                    "Structured tool calls empty — falling back to text parsing (\(fallbackCalls.count) call(s))."
                )
                for (index, call) in fallbackCalls.enumerated() {
                    let argsJson =
                        (try? SerializationUtils.jsonEncoder.encode(call.arguments))
                            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                    context.toolCallAccumulators[index] = (id: UUID().uuidString, name: call.name, args: argsJson)
                }

                for (index, value) in context.toolCallAccumulators.sorted(by: { $0.key < $1.key }) {
                    context.continuation.yield(
                        .toolCall(ToolCallDelta(index: index, id: value.id, name: value.name, arguments: value.args))
                    )
                }
            }
        }

        // Remove sentinel/empty calls so downstream stages see only actionable tool calls.
        context.toolCallAccumulators = context.toolCallAccumulators.filter { _, value in
            !value.name.isEmpty && value.name != ChatEngine.Constants.sentinelToolName
        }

        // Record for the debug snapshot.
        for (_, value) in context.toolCallAccumulators.sorted(by: { $0.key < $1.key }) {
            context.debugToolCalls.append(
                ToolCallRecord(name: value.name, arguments: value.args, turn: context.turnCount)
            )
        }
    }
}

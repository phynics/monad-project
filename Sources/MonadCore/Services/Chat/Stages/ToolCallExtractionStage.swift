import Foundation
import Logging
import MonadShared
import OpenAI

/// Pipeline stage responsible for extracting and normalising tool calls from the LLM response.
///
/// This stage does NOT execute tools. It validates and cleans `context.outputs.toolCallAccumulators`
/// so that `PersistenceStage` and `ChatEngine.runChatLoop` can rely on it:
/// - Falls back to text parsing when the LLM didn't emit structured tool calls.
/// - Strips sentinel and empty-named calls.
/// - Appends records for the debug snapshot.
///
/// Actual execution is handled by `ToolRouter.handlePendingToolCalls()`, called from
/// `ChatEngine.runChatLoop` after the pipeline completes.
struct ToolCallExtractionStage: PipelineStage {
    let logger: Logger

    func process(_ context: ChatTurnContext) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        return AsyncThrowingStream { continuation in
            // Fallback: parse tool calls from response text when structured calls are absent.
            if context.outputs.toolCallAccumulators.isEmpty {
                let fallbackCalls = ToolOutputParser.parse(from: context.outputs.fullResponse)
                if !fallbackCalls.isEmpty {
                    logger.warning(
                        "Structured tool calls empty — falling back to text parsing (\(fallbackCalls.count) call(s))."
                    )
                    for (index, call) in fallbackCalls.enumerated() {
                        let argsJson =
                            (try? SerializationUtils.jsonEncoder.encode(call.arguments))
                                .flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
                        context.outputs.toolCallAccumulators[index] = (
                            id: UUID().uuidString, name: call.name, args: argsJson
                        )
                    }

                    for (index, value) in context.outputs.toolCallAccumulators.sorted(by: { $0.key < $1.key }) {
                        continuation.yield(
                            .toolCall(ToolCallDelta(index: index, id: value.id, name: value.name, arguments: value.args))
                        )
                    }
                }
            }

            // Remove sentinel/empty calls so downstream stages see only actionable tool calls.
            context.outputs.toolCallAccumulators = context.outputs.toolCallAccumulators.filter { _, value in
                !value.name.isEmpty && value.name != ChatEngine.Constants.sentinelToolName
            }

            // Record for the debug snapshot.
            for (_, value) in context.outputs.toolCallAccumulators.sorted(by: { $0.key < $1.key }) {
                context.outputs.debugToolCalls.append(
                    ToolCallRecord(name: value.name, arguments: value.args, turn: context.turnCount)
                )
            }
            continuation.finish()
        }
    }
}

import Foundation
import Logging
import MonadShared
import OpenAI

/// Pipeline stage responsible for streaming the response from the LLM and parsing deltas.
struct LLMStreamingStage: PipelineStage {
    let llmService: any LLMServiceProtocol
    let logger: Logger

    func process(_ context: inout ChatTurnContext) async throws {
        let streamData = await llmService.chatStream(
            messages: context.currentMessages,
            tools: context.toolParams.isEmpty ? nil : context.toolParams,
            responseFormat: nil
        )

        var parser = StreamingParser()
        let turnStartTime = Date()

        for try await result in streamData {
            if Task.isCancelled { break }

            if let usage = result.usage { context.streamUsage = usage }

            if let delta = result.choices.first?.delta.content {
                let oldThinkingCount = parser.thinking.count
                let oldContentCount = parser.content.count

                parser.process(delta)

                let thinkingChunk: Substring
                let contentChunk: Substring

                if parser.hasReclassified {
                    thinkingChunk = parser.thinking.dropFirst(oldThinkingCount)
                    contentChunk = ""
                } else {
                    thinkingChunk = parser.thinking.dropFirst(oldThinkingCount)
                    contentChunk = parser.content.dropFirst(oldContentCount)
                }

                if !thinkingChunk.isEmpty {
                    context.fullThinking += thinkingChunk
                    context.continuation.yield(.thinking(String(thinkingChunk)))
                }

                if !contentChunk.isEmpty {
                    context.fullResponse += contentChunk
                    context.continuation.yield(.generation(String(contentChunk)))
                }
            }

            if let calls = result.choices.first?.delta.toolCalls {
                for call in calls {
                    guard let index = call.index else { continue }
                    var acc = context.toolCallAccumulators[index] ?? ("", "", "")
                    if let id = call.id { acc.id = id }
                    if let name = call.function?.name { acc.name += name }
                    if let args = call.function?.arguments { acc.args += args }
                    context.toolCallAccumulators[index] = acc

                    context.continuation.yield(.toolCall(ToolCallDelta(
                        index: index,
                        id: call.id,
                        name: call.function?.name,
                        arguments: call.function?.arguments
                    )))
                }
            }
        }

        if !parser.buffer.isEmpty {
            if parser.isThinking {
                context.fullThinking += parser.buffer
                context.continuation.yield(.thinking(parser.buffer))
            } else {
                context.fullResponse += parser.buffer
                context.continuation.yield(.generation(parser.buffer))
            }
        }

        context.accumulatedRawOutput += context.fullThinking
        context.accumulatedRawOutput += context.fullResponse
        context.turnDuration = Date().timeIntervalSince(turnStartTime)

        let completionTokens = context.streamUsage?.completionTokens
            ?? TokenEstimator.estimate(text: context.fullResponse + context.fullThinking)
        context.tokensPerSecond = context.turnDuration > 0
            ? Double(completionTokens) / context.turnDuration : nil

        if Task.isCancelled { throw CancellationError() }
    }
}

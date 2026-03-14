import Foundation
import Logging
import MonadShared
import OpenAI

/// Pipeline stage responsible for streaming the response from the LLM and parsing deltas.
struct LLMStreamingStage: PipelineStage {
    let llmService: any LLMServiceProtocol
    let logger: Logger

    func process(_ context: ChatTurnContext) async throws -> AsyncThrowingStream<ChatEvent, Error> {
        let streamData = await llmService.chatStream(
            messages: context.currentMessages,
            tools: context.toolParams.isEmpty ? nil : context.toolParams,
            responseFormat: nil
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parser = StreamingParser()
                    let turnStartTime = Date()

                    for try await result in streamData {
                        if Task.isCancelled { break }

                        if let usage = result.usage { context.outputs.streamUsage = usage }

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
                                context.outputs.fullThinking += thinkingChunk
                                continuation.yield(.thinking(String(thinkingChunk)))
                            }

                            if !contentChunk.isEmpty {
                                context.outputs.fullResponse += contentChunk
                                continuation.yield(.generation(String(contentChunk)))
                            }
                        }

                        if let calls = result.choices.first?.delta.toolCalls {
                            for call in calls {
                                guard let index = call.index else { continue }
                                var acc = context.outputs.toolCallAccumulators[index] ?? ("", "", "")
                                if let id = call.id { acc.id = id }
                                if let name = call.function?.name { acc.name += name }
                                if let args = call.function?.arguments { acc.args += args }
                                context.outputs.toolCallAccumulators[index] = acc

                                continuation.yield(.toolCall(ToolCallDelta(
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
                            context.outputs.fullThinking += parser.buffer
                            continuation.yield(.thinking(parser.buffer))
                        } else {
                            context.outputs.fullResponse += parser.buffer
                            continuation.yield(.generation(parser.buffer))
                        }
                    }

                    context.outputs.accumulatedRawOutput += context.outputs.fullThinking
                    context.outputs.accumulatedRawOutput += context.outputs.fullResponse
                    context.outputs.turnDuration = Date().timeIntervalSince(turnStartTime)

                    let completionTokens = context.outputs.streamUsage?.completionTokens
                        ?? TokenEstimator.estimate(text: context.outputs.fullResponse + context.outputs.fullThinking)
                    context.outputs.tokensPerSecond = context.outputs.turnDuration > 0
                        ? Double(completionTokens) / context.outputs.turnDuration : nil

                    // Task cancellation after natural stream completion is not an error.
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

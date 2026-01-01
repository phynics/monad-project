import Foundation
import Observation
import OpenAI
import os.log

/// Coordinates streaming LLM responses and manages parsing state
@MainActor
@Observable
class StreamingCoordinator {
    var streamingThinking: String = ""
    var streamingContent: String = ""
    var isStreaming = false

    private var parser = StreamingParser()
    private var responseMetadata: APIResponseMetadata?
    private var accumulatedToolCalls: [String: ToolCallAccumulator] = [:]

    /// Process a streaming chunk
    func processChunk(_ delta: String) {
        let (newThinking, newContent, isReclassified) = parser.process(delta)

        if isReclassified {
            Logger.ui.warning("RECLASSIFYING UI STATE: moving content to thinking")
            streamingThinking = newThinking ?? ""
            streamingContent = newContent ?? ""
        } else {
            if let thinking = newThinking {
                streamingThinking += thinking
            }
            if let content = newContent {
                streamingContent += content
            }
        }
    }

    /// Process tool calls from streaming delta
    func processToolCalls(_ toolCalls: [Any]?) {
        guard let toolCalls = toolCalls else { return }

        for toolCall in toolCalls {
            // Use reflection to extract properties
            let mirror = Mirror(reflecting: toolCall)
            var id: String?
            var name: String?
            var arguments: String?

            for child in mirror.children {
                switch child.label {
                case "id":
                    id = child.value as? String
                case "function":
                    let functionMirror = Mirror(reflecting: child.value)
                    for funcChild in functionMirror.children {
                        switch funcChild.label {
                        case "name":
                            name = funcChild.value as? String
                        case "arguments":
                            arguments = funcChild.value as? String
                        default:
                            break
                        }
                    }
                default:
                    break
                }
            }

            guard let callId = id ?? name else { continue }

            // Get or create accumulator for this tool call
            var accumulator = accumulatedToolCalls[callId] ?? ToolCallAccumulator(id: callId)

            // Accumulate name
            if let name = name {
                accumulator.name += name
            }

            // Accumulate arguments
            if let arguments = arguments {
                accumulator.arguments += arguments
            }

            accumulatedToolCalls[callId] = accumulator
        }
    }

    /// Update metadata from streaming result
    func updateMetadata(from result: ChatStreamResult) {
        if responseMetadata == nil {
            responseMetadata = APIResponseMetadata(
                model: result.model,
                promptTokens: nil,
                completionTokens: nil,
                totalTokens: nil,
                finishReason: result.choices.first?.finishReason?.rawValue,
                systemFingerprint: result.systemFingerprint
            )
        }

        if let finishReason = result.choices.first?.finishReason {
            responseMetadata?.finishReason = finishReason.rawValue
        }
    }

    /// Finalize the stream and return the complete message
    func finalize(wasCancelled: Bool) -> Message {
        let (thinking, contentWithoutThink) = parser.finalize()

        // 1. Extract tool calls from XML in content (if any)
        let (finalContent, xmlToolCalls) = parser.extractToolCalls(from: contentWithoutThink)

        var displayContent = finalContent
        if wasCancelled && !streamingContent.isEmpty {
            displayContent = streamingContent
        }

        var originalResponse = ""
        if let thinking = thinking, !thinking.isEmpty {
            originalResponse += "<think>\(thinking)</think>\n"
        }
        originalResponse += contentWithoutThink

        // 2. Combine with native tool calls (if any)
        var toolCalls: [ToolCall] = []

        // Native tool calls from accumulated chunks
        if !accumulatedToolCalls.isEmpty {
            let nativeCalls: [ToolCall] = accumulatedToolCalls.values.compactMap { accumulator in
                guard !accumulator.name.isEmpty else { return nil }

                // Parse arguments JSON
                guard let data = accumulator.arguments.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    Logger.ui.error("Failed to parse tool call arguments: \(accumulator.arguments)")
                    return nil
                }

                // Convert [String: Any] to [String: String]
                var stringArgs: [String: String] = [:]
                for (key, value) in json {
                    stringArgs[key] = "\(value)"
                }

                return ToolCall(name: accumulator.name, arguments: stringArgs)
            }
            toolCalls.append(contentsOf: nativeCalls)
        }

        // XML tool calls
        toolCalls.append(contentsOf: xmlToolCalls)

        let finalToolCalls = toolCalls.isEmpty ? nil : toolCalls

        let message = Message(
            content: displayContent.isEmpty ? "[Cancelled]" : displayContent,
            role: .assistant,
            think: thinking,
            toolCalls: finalToolCalls,
            debugInfo: responseMetadata.map {
                .assistantMessage(
                    response: $0,
                    original: originalResponse,
                    parsed: displayContent,
                    thinking: thinking,
                    toolCalls: finalToolCalls
                )
            }
        )

        return message
    }

    /// Start a new streaming session
    func startStreaming() {
        isStreaming = true
        streamingThinking = ""
        streamingContent = ""
        parser.reset()
        responseMetadata = nil
        accumulatedToolCalls = [:]
    }

    /// Stop streaming and reset state
    func stopStreaming() {
        isStreaming = false
        streamingThinking = ""
        streamingContent = ""
    }

    /// Get current metadata
    func getMetadata() -> APIResponseMetadata? {
        responseMetadata
    }
}

// MARK: - Tool Call Accumulator

/// Accumulates tool call chunks during streaming
private struct ToolCallAccumulator {
    let id: String
    var name: String = ""
    var arguments: String = ""
}

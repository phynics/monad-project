import Foundation
import Logging
import Observation
import OpenAI

@MainActor
@Observable
public final class StreamingCoordinator {
    // MARK: - Properties

    // Core state
    public var streamingContent: String = ""
    public var streamingThinking: String = ""
    public var isStreaming: Bool = false
    public var startTime: Date?
    public var usage: ChatResult.CompletionUsage?

    // Accumulators
    private var accumulatedToolCalls: [Int: ToolCallAccumulator] = [:]
    private var currentToolCallIndex: Int?

    // Parser
    @ObservationIgnored
    private var parser = StreamingParser()
    private let logger = Logger.module(named: "chat")

    public init() {}

    // MARK: - Actions

    public func startStreaming() {
        // Reset state
        streamingContent = ""
        streamingThinking = ""
        accumulatedToolCalls = [:]
        currentToolCallIndex = nil
        isStreaming = true
        startTime = Date()
        usage = nil
        parser = StreamingParser()
        logger.debug("Started streaming")
    }

    public func stopStreaming() {
        isStreaming = false
        logger.debug("Stopped streaming. Final content length: \(streamingContent.count)")
    }

    public func updateMetadata(from result: ChatStreamResult) {
        // Update usage stats if provided in stream
        if let usage = result.usage {
            self.usage = usage
        }
    }

    public func processChunk(_ delta: String) {
        logger.debug("PARSING CHUNK: '\(delta)'")
        // Parse the chunk using our parser (handles <think> tags)
        parser.process(delta)

        if parser.hasReclassified {
            logger.warning("PARSER RECLASSIFIED STATE: content moved to thinking")
            streamingThinking = parser.thinking
            streamingContent = parser.content
        } else {
            streamingThinking = parser.thinking
            streamingContent = parser.content
        }
    }

    /// Check for native tool calls in the stream delta
    /// Using [Any] to avoid deep type nesting issues with OpenAI library
    public func processToolCalls(_ toolCalls: [Any]) {
        logger.debug("Received \(toolCalls.count) native tool call deltas")
        for toolCall in toolCalls {
            // Use reflection to extract properties safely
            let mirror = Mirror(reflecting: toolCall)
            var id: String?
            var name: String?
            var arguments: String?
            var index: Int?

            for child in mirror.children {
                switch child.label {
                case "index":
                    index = child.value as? Int
                case "id":
                    id = child.value as? String
                case "function":
                    // Function is likely another struct we need to reflect on
                    // Handle Optional unwrapping for function property
                    var functionValue = child.value
                    let functionMirror = Mirror(reflecting: functionValue)
                    if functionMirror.displayStyle == .optional, let (_, some) = functionMirror.children.first {
                        functionValue = some
                    }

                    let funcMirror = Mirror(reflecting: functionValue)
                    for funcChild in funcMirror.children {
                        switch funcChild.label {
                        case "name":
                            // Unwrap optional name if needed
                            if let str = funcChild.value as? String {
                                name = str
                            } else {
                                let nameMirror = Mirror(reflecting: funcChild.value)
                                if nameMirror.displayStyle == .optional, let (_, some) = nameMirror.children.first {
                                    name = some as? String
                                }
                            }
                        case "arguments":
                            // Unwrap optional arguments if needed
                            if let str = funcChild.value as? String {
                                arguments = str
                            } else {
                                let argsMirror = Mirror(reflecting: funcChild.value)
                                if argsMirror.displayStyle == .optional, let (_, some) = argsMirror.children.first {
                                    arguments = some as? String
                                }
                            }
                        default:
                            break
                        }
                    }
                default:
                    break
                }
            }

            guard let idx = index else { continue }

            // Initialize accumulator if needed
            if accumulatedToolCalls[idx] == nil {
                accumulatedToolCalls[idx] = ToolCallAccumulator()
                currentToolCallIndex = idx
            }

            // Accumulate parts
            if let name = name {
                accumulatedToolCalls[idx]?.name += name
            }

            if let arguments = arguments {
                accumulatedToolCalls[idx]?.arguments += arguments
            }
        }
    }

    public func finalize(
        wasCancelled: Bool = false
    ) -> Message {
        // flush manually if any remaining text
        if !parser.buffer.isEmpty {
            if parser.isThinking {
                streamingThinking += parser.buffer
            } else {
                streamingContent += parser.buffer
            }
        }

        let finalThinking = streamingThinking.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = streamingContent.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Extract XML tools from the content
        let (contentWithoutTools, xmlToolCalls) = parser.extractToolCalls(from: finalContent)

        // 2. Combine native tools and XML tools
        var finalToolCalls: [ToolCall] = []

        // Native tool calls from accumulated chunks
        if !accumulatedToolCalls.isEmpty {
            let nativeCalls = accumulatedToolCalls.values.compactMap { accumulator -> ToolCall? in
                guard !accumulator.name.isEmpty else { return nil }

                // Parse arguments JSON
                var args: [String: AnyCodable] = [:]
                if let data = accumulator.arguments.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Convert [String: Any] -> [String: AnyCodable]
                    args = json.mapValues { AnyCodable($0) }
                } else if !accumulator.arguments.isEmpty {
                    // Fallback for simple string arguments if JSON parsing fails but content exists
                    // This might happen if the LLM produces malformed JSON.
                    // For now, we leave it empty or could try to fix it.
                    // But strictly, ToolCall expects [String: AnyCodable]
                }

                return ToolCall(
                    name: accumulator.name,
                    arguments: args
                )
            }
            finalToolCalls.append(contentsOf: nativeCalls)
        }

        // Append XML extracted tools
        finalToolCalls.append(contentsOf: xmlToolCalls)

        if !finalToolCalls.isEmpty {
            logger.info("Finalized with \(finalToolCalls.count) tool calls")
        }

        if wasCancelled {
            logger.notice("Streaming cancelled")
        }

        // Create final message
        return Message(
            content: contentWithoutTools,
            role: .assistant,
            think: finalThinking.isEmpty ? nil : finalThinking,
            toolCalls: finalToolCalls.isEmpty ? nil : finalToolCalls
        )
    }
}

// MARK: - Helper Types

private struct ToolCallAccumulator {
    var name: String = ""
    var arguments: String = ""
}

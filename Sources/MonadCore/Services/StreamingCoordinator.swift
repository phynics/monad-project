import Foundation
import OSLog
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

    // Accumulators
    private var accumulatedToolCalls: [Int: ToolCallAccumulator] = [:]
    private var currentToolCallIndex: Int?

    // Parser
    private let parser = StreamingParser()
    private let logger = Logger.chat

    public init() {}

    // MARK: - Actions

    public func startStreaming() {
        // Reset state
        streamingContent = ""
        streamingThinking = ""
        accumulatedToolCalls = [:]
        currentToolCallIndex = nil
        isStreaming = true
        parser.reset()
        logger.debug("Started streaming")
    }

    public func stopStreaming() {
        isStreaming = false
        logger.debug("Stopped streaming. Final content length: \(self.streamingContent.count)")
    }

    public func updateMetadata(from result: ChatStreamResult) {
        // Update basic metadata if needed (e.g. usage stats if provided in stream)
    }

    public func processChunk(_ delta: String) {
        // Parse the chunk using our parser (handles <think> tags)
        let (newThinking, newContent, isReclassified) = parser.process(delta)

        if isReclassified {
            logger.warning("RECLASSIFYING UI STATE: moving content to thinking")
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

    // Check for native tool calls in the stream delta
    // Using [Any] to avoid deep type nesting issues with OpenAI library
    public func processToolCalls(_ toolCalls: [Any]) {
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

            if let id = id {
                accumulatedToolCalls[idx]?.id = id
            }
        }
    }

    public func finalize(wasCancelled: Bool = false) -> Message {
        // 1. Extract XML tools from the content
        let (contentWithoutTools, xmlToolCalls) = parser.extractToolCalls(from: streamingContent)

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
            // Only include think block if it's not empty
            think: streamingThinking.isEmpty ? nil : streamingThinking,
            toolCalls: finalToolCalls.isEmpty ? nil : finalToolCalls
        )
    }
}

// MARK: - Helper Types

private struct ToolCallAccumulator {
    var id: String?
    var name: String = ""
    var arguments: String = ""
}

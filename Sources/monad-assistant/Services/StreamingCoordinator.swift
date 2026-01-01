import Foundation
import Observation
import OpenAI
import os.log

@MainActor
@Observable
class StreamingCoordinator {
    // MARK: - Properties

    // Core state
    var streamingContent: String = ""
    var streamingThinking: String = ""
    var isStreaming = false

    // Accumulators
    private var accumulatedToolCalls: [Int: ToolCallAccumulator] = [:]
    private var currentToolCallIndex: Int?

    // Parser
    private let parser = StreamingParser()
    private let logger = Logger.chat

    // MARK: - Actions

    func startStreaming() {
        // Reset state
        isStreaming = true
        streamingContent = ""
        streamingThinking = ""
        accumulatedToolCalls = [:]
        currentToolCallIndex = nil
        parser.reset()
        logger.debug("Started streaming")
    }

    func stopStreaming() {
        isStreaming = false
        logger.debug("Stopped streaming. Final content length: \(self.streamingContent.count)")
    }

    func updateMetadata(from result: ChatStreamResult) {
        // Update basic metadata if needed (e.g. usage stats if provided in stream)
    }

    func processChunk(_ delta: String) {
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
    func processToolCalls(_ toolCalls: [Any]) {
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
                    let funcMirror = Mirror(reflecting: child.value)
                    for funcChild in funcMirror.children {
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

    func finalize(wasCancelled: Bool = false) -> Message {
        // 1. Extract XML tools from the content
        let (contentWithoutTools, xmlToolCalls) = parser.extractToolCalls(from: streamingContent)

        // 2. Combine native tools and XML tools
        var finalToolCalls: [ToolCall] = []

        // Native tool calls from accumulated chunks
        if !accumulatedToolCalls.isEmpty {
            let nativeCalls = accumulatedToolCalls.values.compactMap { accumulator -> ToolCall? in
                guard !accumulator.name.isEmpty else { return nil }

                // Parse arguments JSON
                var args: [String: Any]?
                if let data = accumulator.arguments.data(using: .utf8) {
                    args = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                }

                // Convert arguments to [String: String]
                var stringArgs: [String: String] = [:]
                if let args = args {
                    for (key, value) in args {
                        stringArgs[key] = "\(value)"
                    }
                }

                return ToolCall(
                    name: accumulator.name,
                    arguments: stringArgs
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

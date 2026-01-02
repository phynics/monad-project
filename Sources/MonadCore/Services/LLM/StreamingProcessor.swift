import Foundation
import OSLog

/// Logic for processing LLM streams and accumulating tool calls (Pure Logic)
public struct StreamingProcessor {
    // Parser
    private let parser = StreamingParser()
    private let logger = Logger(subsystem: "com.monad.core", category: "streaming-processor")

    // Accumulators
    private var accumulatedToolCalls: [Int: ToolCallAccumulator] = [:]
    private var currentToolCallIndex: Int?

    // State
    public var streamingContent: String = ""
    public var streamingThinking: String = ""

    public init() {}

    public mutating func reset() {
        streamingContent = ""
        streamingThinking = ""
        accumulatedToolCalls = [:]
        currentToolCallIndex = nil
        parser.reset()
    }

    public mutating func processChunk(_ delta: String) {
        let (newThinking, newContent, isReclassified) = parser.process(delta)

        if isReclassified {
            logger.warning("RECLASSIFYING: moving content to thinking")
            // If reclassified, the parser has moved what was previously considered content into thinking.
            // We should trust the parser's output for the *current* state of the stream?
            // The parser returns incremental updates. But if reclassified, it might be returning a large chunk of "newThinking" which was the old content.
            // To be safe and sync with parser state:
            // We should reset our local buffers and rebuild? No, we don't have the full history here easily unless we keep it.
            // But `StreamingParser` logic says:
            // if isReclassified: thinkingBuffer = contentBuffer + actualText; contentBuffer = ""; newThinking = thinkingBuffer; newContent = ""
            // So `newThinking` contains the FULL thinking buffer (old content + new text).
            // And `newContent` is empty.
            // So we should replace `streamingThinking` with `newThinking`.
            // And we should probably clear `streamingContent`?
            // The parser's `contentBuffer` is cleared.
            // So if we simply append `newContent` (empty) to `streamingContent` (not empty), we get a mess.
            // We need to clear `streamingContent`.

            if let validThinking = newThinking {
                streamingThinking = validThinking
            }
            streamingContent = "" // Clear content as it was moved to thinking
        } else {
            if let thinking = newThinking {
                streamingThinking += thinking
            }
            if let content = newContent {
                streamingContent += content
            }
        }
    }

    public mutating func processToolCalls(_ toolCalls: [Any]) {
        for toolCall in toolCalls {
            // Use reflection to extract properties safely (as in original code)
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

            if accumulatedToolCalls[idx] == nil {
                accumulatedToolCalls[idx] = ToolCallAccumulator()
                currentToolCallIndex = idx
            }

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

    public mutating func finalize(wasCancelled: Bool = false) -> Message {
        let (contentWithoutTools, xmlToolCalls) = parser.extractToolCalls(from: streamingContent)

        var finalToolCalls: [ToolCall] = []

        if !accumulatedToolCalls.isEmpty {
            let nativeCalls = accumulatedToolCalls.values.compactMap { accumulator -> ToolCall? in
                guard !accumulator.name.isEmpty else { return nil }

                var args: [String: Any]?
                if let data = accumulator.arguments.data(using: .utf8) {
                    args = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                }

                var stringArgs: [String: String] = [:]
                if let args = args {
                    for (key, value) in args {
                        stringArgs[key] = "\(value)"
                    }
                }

                return ToolCall(name: accumulator.name, arguments: stringArgs)
            }
            finalToolCalls.append(contentsOf: nativeCalls)
        }

        finalToolCalls.append(contentsOf: xmlToolCalls)

        return Message(
            content: contentWithoutTools,
            role: .assistant,
            think: streamingThinking.isEmpty ? nil : streamingThinking,
            toolCalls: finalToolCalls.isEmpty ? nil : finalToolCalls
        )
    }
}

// Helper struct
private struct ToolCallAccumulator {
    var id: String?
    var name: String = ""
    var arguments: String = ""
}

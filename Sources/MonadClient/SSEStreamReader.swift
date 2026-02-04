import Foundation
import Logging

/// Parses Server-Sent Events (SSE) from an async byte stream
public struct SSEStreamReader: Sendable {
    public init() {}

    /// Parse SSE events from a URL response
    public func events(from bytes: URLSession.AsyncBytes, logger: Logger)
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var buffer = ""

                    for try await byte in bytes {
                        let char = Character(UnicodeScalar(byte))
                        buffer.append(char)

                        // Check for complete SSE message (ends with double newline)
                        while let range = buffer.range(of: "\n\n") {
                            let message = String(buffer[..<range.lowerBound])
                            logger.debug("Received SSE message: \(message.prefix(100))...")
                            buffer = String(buffer[range.upperBound...])

                            if let delta = parseSSEMessage(message) {
                                if delta.isDone {
                                    logger.debug("Stream done")
                                    continuation.finish()
                                    return
                                }
                                continuation.yield(delta)
                            } else {
                                logger.error("Failed to parse SSE message")
                            }
                        }
                    }
                    logger.debug("Byte stream ended")

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse a single SSE message
    private func parseSSEMessage(_ message: String) -> ChatDelta? {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))

                // Check for done marker
                if data == "[DONE]" {
                    return ChatDelta(isDone: true)
                }

                // Try to parse JSON
                if let jsonData = data.data(using: .utf8) {
                    // 1. Try to decode as ChatDelta directly (New Structured Format)
                    if let delta = try? JSONDecoder().decode(ChatDelta.self, from: jsonData) {
                        return delta
                    }

                    // 2. Fallback to OpenAI-style delta (Legacy / Interop)
                    do {
                        if let json = try JSONSerialization.jsonObject(with: jsonData)
                            as? [String: Any],
                            let choices = json["choices"] as? [[String: Any]],
                            let firstChoice = choices.first,
                            let delta = firstChoice["delta"] as? [String: Any]
                        {
                            let content = delta["content"] as? String

                            // Extract tool calls if present
                            var toolCallDeltas: [ToolCallDelta]? = nil
                            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                                toolCallDeltas = toolCalls.compactMap { dict in
                                    guard let index = dict["index"] as? Int else { return nil }
                                    let id = dict["id"] as? String
                                    let function = dict["function"] as? [String: Any]
                                    let name = function?["name"] as? String
                                    let arguments = function?["arguments"] as? String
                                    return ToolCallDelta(
                                        index: index, id: id, name: name, arguments: arguments)
                                }
                            }

                            return ChatDelta(content: content, toolCalls: toolCallDeltas)
                        }
                    } catch {
                        // If JSON parsing fails, treat as plain text
                        return ChatDelta(content: data)
                    }
                }
            }
        }

        return nil
    }
}

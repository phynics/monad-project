import Foundation
import MonadCore
import MonadShared
import Logging

/// Parses Server-Sent Events (SSE) from an async byte stream
public struct SSEStreamReader: Sendable {
    public init() {}

    /// Parse SSE events from a URL response
    public func events(from bytes: URLSession.AsyncBytes, logger: Logger)
        -> AsyncThrowingStream<ChatEvent, Error> {
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

                            if let event = parseSSEMessage(message) {
                                if case .completion(.streamCompleted) = event {
                                    logger.debug("Stream done")
                                    continuation.finish()
                                    return
                                }
                                continuation.yield(event)
                            } else {
                                logger.debug("Skipping unparseable SSE message")
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
    private func parseSSEMessage(_ message: String) -> ChatEvent? {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)

        for line in lines {
            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))

                // Try to parse JSON using the shared decoder (ISO 8601 dates)
                if let jsonData = data.data(using: .utf8) {
                    return try? SerializationUtils.jsonDecoder.decode(ChatEvent.self, from: jsonData)
                }
            }
        }

        return nil
    }
}

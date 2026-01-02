import Foundation
import OSLog
import Observation
import OpenAI
import MonadCore

@MainActor
@Observable
public final class StreamingCoordinator {
    // MARK: - Properties

    // Core state
    public var streamingContent: String = ""
    public var streamingThinking: String = ""
    public var isStreaming: Bool = false

    // Core logic processor
    private var processor = StreamingProcessor()
    private let logger = Logger(subsystem: "com.monad.shared", category: "streaming-coordinator")

    public init() {}

    // MARK: - Actions

    public func startStreaming() {
        streamingContent = ""
        streamingThinking = ""
        isStreaming = true
        processor.reset()
        logger.debug("Started streaming")
    }

    public func stopStreaming() {
        isStreaming = false
        logger.debug("Stopped streaming. Final content length: \(self.streamingContent.count)")
    }

    public func updateMetadata(from result: ChatStreamResult) {
        // Update basic metadata if needed
    }

    public func processChunk(_ delta: String) {
        processor.processChunk(delta)
        // Sync state from processor
        self.streamingContent = processor.streamingContent
        self.streamingThinking = processor.streamingThinking
    }

    public func processToolCalls(_ toolCalls: [Any]) {
        processor.processToolCalls(toolCalls)
    }

    public func finalize(wasCancelled: Bool = false) -> Message {
        let message = processor.finalize(wasCancelled: wasCancelled)

        if wasCancelled {
            logger.notice("Streaming cancelled")
        }

        return message
    }
}

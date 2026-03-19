import Foundation
import Logging
import MonadShared

/// Pipeline stage responsible for assembling the gathered results into a final `ContextData` object.
public struct ContextAssemblyStage: PipelineStage {
    /// Logger for assembly progress.
    public let logger: Logger

    /// Initializes a new assembly stage.
    /// - Parameter logger: The logger to use.
    public init(logger: Logger) {
        self.logger = logger
    }

    /// Processes the context and yields a completion event with final data.
    /// - Parameter context: The shared pipeline context.
    /// - Returns: A stream that yields the final result.
    public func process(
        _ context: ContextPipelineContext
    ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        let startTime = context.startTime
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("Context gathered in \(String(format: "%.3f", duration))s")

        let results = await context.getResults()
        let augmentedQuery = await context.augmentedQuery
        let data = ContextData(
            notes: results.notes,
            memories: results.memories,
            generatedTags: results.tags,
            queryVector: results.vector,
            augmentedQuery: augmentedQuery,
            semanticResults: results.semanticResults,
            tagResults: results.tagResults,
            executionTime: duration
        )
        await context.setContextData(data)
        return AsyncThrowingStream { $0.finish() }
    }
}

import Foundation
import Logging
import MonadShared

/// Pipeline stage responsible for assembling the gathered results into a final `ContextData` object.
public struct ContextAssemblyStage: PipelineStage {
    public let logger: Logger

    public init(logger: Logger) {
        self.logger = logger
    }

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

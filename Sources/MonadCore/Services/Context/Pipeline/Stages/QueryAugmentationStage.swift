import Foundation
import MonadShared

/// Pipeline stage responsible for augmenting the search query with recent conversation history.
public struct QueryAugmentationStage: PipelineStage {
    public let manager: ContextManager

    public init(manager: ContextManager) {
        self.manager = manager
    }

    public func process(
        _ context: ContextPipelineContext
    ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        let query = context.query
        let history = context.history
        let augmented = manager.buildAugmentedContext(query: query, history: history)
        await context.setAugmentedQuery(augmented)

        return AsyncThrowingStream { continuation in
            continuation.yield(.progress(.augmenting))
            continuation.finish()
        }
    }
}

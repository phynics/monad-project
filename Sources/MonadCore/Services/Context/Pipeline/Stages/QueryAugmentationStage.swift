import Foundation
import Logging
import MonadShared

/// Pipeline stage responsible for augmenting the search query with recent conversation history.
public struct QueryAugmentationStage: PipelineStage {
    private let logger = Logger.module(named: "com.monad.QueryAugmentationStage")

    public init() {}

    public func process(
        _ context: ContextPipelineContext
    ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        let query = context.query
        let history = context.history
        
        let augmented = buildAugmentedContext(query: query, history: history)
        await context.setAugmentedQuery(augmented)

        return AsyncThrowingStream { continuation in
            continuation.yield(.progress(.augmenting))
            continuation.finish()
        }
    }

    private func buildAugmentedContext(query: String, history: [Message]) -> String {
        guard !history.isEmpty else { return query }

        // Take the last few user/assistant messages to provide context for tags
        // Exclude tool responses as they might be too technical/long for tag generation context
        let historyContext =
            history
                .filter { $0.role == .user || $0.role == .assistant }
                .suffix(3)
                .map { $0.content }
                .joined(separator: " ")

        if historyContext.isEmpty { return query }

        let augmented = "\(historyContext) \(query)"
        logger.debug("Augmented tag context: \(augmented)")
        return augmented
    }
}

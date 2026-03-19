import Foundation
import MonadShared

/// Pipeline stage responsible for retrieving relevant semantic memories and tags.
public struct MemoryRetrievalStage: PipelineStage {
    public let manager: ContextManager

    public init(manager: ContextManager) {
        self.manager = manager
    }

    public func process(
        _ context: ContextPipelineContext
    ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        let query = context.query
        let augmentedQuery = await context.augmentedQuery
        let limit = context.limit
        let tagGenerator = context.tagGenerator

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let memoriesData = try await manager.fetchRelevantMemories(
                        for: query,
                        tagContext: augmentedQuery,
                        limit: limit,
                        tagGenerator: tagGenerator,
                        onProgress: { progress in
                            continuation.yield(.progress(progress))
                        }
                    )
                    await context.setResults(
                        memories: memoriesData.memories,
                        tags: memoriesData.tags,
                        vector: memoriesData.vector,
                        semanticResults: memoriesData.semanticResults,
                        tagResults: memoriesData.tagResults
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

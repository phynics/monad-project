import Foundation
import MonadShared

/// Pipeline stage responsible for discovering relevant filesystem notes in the workspace.
public struct NoteDiscoveryStage: PipelineStage {
    public let manager: ContextManager

    public init(manager: ContextManager) {
        self.manager = manager
    }

    public func process(
        _ context: ContextPipelineContext
    ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.progress(.discoveringNotes))
                let notes = (try? await manager.fetchAllNotes()) ?? []
                await context.setResults(notes: notes)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

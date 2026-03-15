import Dependencies
import ErrorKit
import Foundation
import Logging
import MonadShared

/// Manages the retrieval and organization of context for the chat
public actor ContextManager {
    @Dependency(\.memoryStore) var memoryStore
    @Dependency(\.embeddingService) var embeddingService

    let workspace: (any WorkspaceProtocol)?
    let logger = Logger.module(named: "com.monad.ContextManager")

    let ranker = ContextRanker()

    public init(
        workspace: (any WorkspaceProtocol)? = nil
    ) {
        self.workspace = workspace
    }

    // MARK: - Pipeline Types

    private final class ContextGatheringContext: @unchecked Sendable {
        let query: String
        let history: [Message]
        let limit: Int
        let tagGenerator: (@Sendable (String) async throws -> [String])?

        var startTime: CFAbsoluteTime = 0
        var augmentedQuery: String = ""
        var notes: [ContextFile] = []
        var memories: [SemanticSearchResult] = []
        var generatedTags: [String] = []
        var queryVector: [Double] = []
        var semanticResults: [SemanticSearchResult] = []
        var tagResults: [Memory] = []

        var contextData: ContextData?

        init(
            query: String,
            history: [Message],
            limit: Int,
            tagGenerator: (@Sendable (String) async throws -> [String])?,
            startTime: CFAbsoluteTime
        ) {
            self.query = query
            self.history = history
            self.limit = limit
            self.tagGenerator = tagGenerator
            self.startTime = startTime
        }
    }

    private struct QueryAugmentationStage: PipelineStage {
        let manager: ContextManager

        func process(
            _ context: ContextGatheringContext
        ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
            return AsyncThrowingStream { continuation in
                continuation.yield(.progress(.augmenting))
                context.augmentedQuery = manager.buildAugmentedContext(query: context.query, history: context.history)
                continuation.finish()
            }
        }
    }

    private struct MemoryRetrievalStage: PipelineStage {
        let manager: ContextManager

        func process(
            _ context: ContextGatheringContext
        ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        let memoriesData = try await manager.fetchRelevantMemories(
                            for: context.query,
                            tagContext: context.augmentedQuery,
                            limit: context.limit,
                            tagGenerator: context.tagGenerator,
                            onProgress: { progress in
                                continuation.yield(.progress(progress))
                            }
                        )
                        context.memories = memoriesData.memories
                        context.generatedTags = memoriesData.tags
                        context.queryVector = memoriesData.vector
                        context.semanticResults = memoriesData.semanticResults
                        context.tagResults = memoriesData.tagResults
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }
    }

    private struct NoteDiscoveryStage: PipelineStage {
        let manager: ContextManager

        func process(
            _ context: ContextGatheringContext
        ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(.progress(.discoveringNotes))
                    context.notes = (try? await manager.fetchAllNotes()) ?? []
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }
    }

    private struct ContextAssemblyStage: PipelineStage {
        let logger: Logger

        func process(
            _ context: ContextGatheringContext
        ) async throws -> AsyncThrowingStream<ContextGatheringEvent, Error> {
            let duration = CFAbsoluteTimeGetCurrent() - context.startTime
            logger.info("Context gathered in \(String(format: "%.3f", duration))s")

            context.contextData = ContextData(
                notes: context.notes,
                memories: context.memories,
                generatedTags: context.generatedTags,
                queryVector: context.queryVector,
                augmentedQuery: context.augmentedQuery,
                semanticResults: context.semanticResults,
                tagResults: context.tagResults,
                executionTime: duration
            )
            return AsyncThrowingStream { $0.finish() }
        }
    }

    /// Events emitted during the context gathering process
    public enum ContextGatheringEvent: Sendable {
        case progress(Message.ContextGatheringProgress)
        case complete(ContextData)
    }

    /// Gather all relevant context for a given user query
    /// - Parameters:
    ///   - query: The user's input text
    ///   - history: Recent conversation history to provide context for the search
    ///   - limit: Maximum number of memories to retrieve
    ///   - tagGenerator: A function to generate tags from the query (e.g. via LLM)
    /// - Returns: A stream of progress events, finishing with the structured context
    public func gatherContext(
        for query: String,
        history: [Message] = [],
        limit: Int = 5,
        tagGenerator: (@Sendable (String) async throws -> [String])? = nil
    ) -> AsyncThrowingStream<ContextGatheringEvent, Error> {
        return AsyncThrowingStream { continuation in
            let task = Task {
                let startTime = CFAbsoluteTimeGetCurrent()
                logger.debug(
                    "Gathering context for query length: \(query.count), history count: \(history.count)"
                )

                let context = ContextGatheringContext(
                    query: query,
                    history: history,
                    limit: limit,
                    tagGenerator: tagGenerator,
                    startTime: startTime
                )

                let pipeline = Pipeline<ContextGatheringContext, ContextGatheringEvent>()
                    .add(QueryAugmentationStage(manager: self))
                    .add(MemoryRetrievalStage(manager: self))
                    .add(NoteDiscoveryStage(manager: self))
                    .add(ContextAssemblyStage(logger: logger))

                do {
                    let stream = pipeline.execute(context)
                    for try await event in stream {
                        continuation.yield(event)
                    }

                    if let data = context.contextData {
                        continuation.yield(.progress(.complete))
                        continuation.yield(.complete(data))
                    }
                    continuation.finish()
                } catch {
                    logger.error("Context gathering failed: \(ErrorKit.userFriendlyMessage(for: error))")
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func fetchAllNotes() async throws -> [ContextFile] {
        var allNotes: [ContextFile] = []

        if let workspace = workspace {
            do {
                let files = try await workspace.listFiles(path: "Notes")

                for filePath in files where filePath.hasSuffix(".md") {
                    guard let content = try? await workspace.readFile(path: filePath) else {
                        continue
                    }
                    let name = URL(fileURLWithPath: filePath).deletingPathExtension().lastPathComponent

                    let note = ContextFile(
                        name: name,
                        content: content,
                        source: filePath
                    )
                    allNotes.append(note)
                }
            } catch {
                logger.warning(
                    "Failed to fetch notes from workspace: \(ErrorKit.userFriendlyMessage(for: error))"
                )
            }
        }

        return allNotes.sorted(by: { $0.name < $1.name })
    }

    private nonisolated func buildAugmentedContext(query: String, history: [Message]) -> String {
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

struct MemoryRetrievalResult {
    let memories: [SemanticSearchResult]
    let tags: [String]
    let vector: [Double]
    let semanticResults: [SemanticSearchResult]
    let tagResults: [Memory]
}

import MonadShared
import Dependencies
import Foundation
import Logging

/// Manages the retrieval and organization of context for the chat
public actor ContextManager: @unchecked Sendable {
    @Dependency(\.memoryStore) var memoryStore
    @Dependency(\.embeddingService) var embeddingService

    private let workspace: (any WorkspaceProtocol)?
    private let logger = Logger.module(named: "com.monad.ContextManager")

    private let ranker = ContextRanker()

    public init(
        workspace: (any WorkspaceProtocol)? = nil
    ) {
        self.workspace = workspace
    }

    // MARK: - Pipeline Types

    private struct ContextGatheringContext {
        let query: String
        let history: [Message]
        let limit: Int
        let tagGenerator: (@Sendable (String) async throws -> [String])?
        let continuation: AsyncThrowingStream<ContextGatheringEvent, Error>.Continuation
        
        var startTime: CFAbsoluteTime = 0
        var augmentedQuery: String = ""
        var notes: [ContextFile] = []
        var memories: [SemanticSearchResult] = []
        var generatedTags: [String] = []
        var queryVector: [Double] = []
        var semanticResults: [SemanticSearchResult] = []
        var tagResults: [Memory] = []
        
        var contextData: ContextData?
    }

    private struct QueryAugmentationStage: PipelineStage {
        let manager: ContextManager

        func process(_ context: inout ContextGatheringContext) async throws {
            context.continuation.yield(.progress(.augmenting))
            context.augmentedQuery = manager.buildAugmentedContext(query: context.query, history: context.history)
        }
    }

    private struct MemoryRetrievalStage: PipelineStage {
        let manager: ContextManager

        func process(_ context: inout ContextGatheringContext) async throws {
            let continuation = context.continuation
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
        }
    }

    private struct NoteDiscoveryStage: PipelineStage {
        let manager: ContextManager

        func process(_ context: inout ContextGatheringContext) async throws {
            context.notes = try await manager.fetchAllNotes()
        }
    }

    private struct ContextAssemblyStage: PipelineStage {
        let logger: Logger

        func process(_ context: inout ContextGatheringContext) async throws {
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

                var context = ContextGatheringContext(
                    query: query,
                    history: history,
                    limit: limit,
                    tagGenerator: tagGenerator,
                    continuation: continuation,
                    startTime: startTime
                )

                let pipeline = Pipeline<ContextGatheringContext>()
                    .add(QueryAugmentationStage(manager: self))
                    .add(MemoryRetrievalStage(manager: self))
                    .add(NoteDiscoveryStage(manager: self))
                    .add(ContextAssemblyStage(logger: logger))

                do {
                    try await pipeline.execute(&context)
                    
                    if let data = context.contextData {
                        continuation.yield(.progress(.complete))
                        continuation.yield(.complete(data))
                    }
                    continuation.finish()
                } catch {
                    logger.error("Context gathering failed: \(error.localizedDescription)")
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

        // 2. Fetch from Workspace
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
                    "Failed to fetch notes from workspace: \(error.localizedDescription)"
                )
            }
        }

        return allNotes.sorted(by: { $0.name < $1.name })
    }

    nonisolated private func buildAugmentedContext(query: String, history: [Message]) -> String {
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

    private func fetchRelevantMemories(
        for query: String,
        tagContext: String,
        limit: Int,
        tagGenerator: (@Sendable (String) async throws -> [String])?,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)?
    ) async throws -> (
        memories: [SemanticSearchResult],
        tags: [String],
        vector: [Double],
        semanticResults: [SemanticSearchResult],
        tagResults: [Memory]
    ) {
        // Validation
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [], [], [], [])
        }

        // 1. Generate Tags (Fault tolerant)
        var tags: [String] = []
        if let generator = tagGenerator {
            onProgress?(.tagging)
            do {
                tags = try await generator(tagContext)
                logger.debug("Generated tags: \(tags)")
            } catch {
                logger.warning("Optional tag generation failed: \(error.localizedDescription)")
                // Non-critical, continue with just embedding
            }
        }

        // 2. Generate Embedding (Critical)
        onProgress?(.embedding)
        let embedding: [Float]
        do {
            embedding = try await embeddingService.generateEmbedding(for: query)
        } catch {
            throw ContextManagerError.embeddingFailed(error)
        }

        // Check cancellation
        if Task.isCancelled { return ([], [], [], [], []) }

        // 3. Parallel Retrieval: Vector Search & Tag Search
        onProgress?(.searching)

        let searchTags = tags // Capture local copy for concurrency safety

        // Convert Float embedding to Double for PersistenceService (GRDB compatibility)
        let doubleEmbedding = embedding.map { Double($0) }

        async let semanticTask = memoryStore.searchMemories(
            embedding: doubleEmbedding,
            limit: limit * 2, // Search for more to allow for tag-boosted re-ranking
            minSimilarity: 0.35 // Slightly lower to catch more candidates for re-ranking
        )

        async let tagTask = memoryStore.searchMemories(matchingAnyTag: searchTags)

        let (rawSemanticResults, tagResults) = try await (semanticTask, tagTask)
        let semanticResults = rawSemanticResults.map {
            SemanticSearchResult(memory: $0.memory, similarity: $0.similarity)
        }

        // 4. Combine and Rank
        onProgress?(.ranking)

        let finalResults = ranker.rankMemories(
            semantic: semanticResults,
            tagBased: tagResults,
            queryEmbedding: doubleEmbedding
        )

        // Take top N based on limit
        let topResults = Array(finalResults.prefix(limit))

        logger.info(
            "Recall performance: \(topResults.count) memories selected from \(semanticResults.count) semantic + \(tagResults.count) tag matches"
        )

        return (
            topResults,
            tags,
            doubleEmbedding,
            semanticResults.map {
                SemanticSearchResult(memory: $0.memory, similarity: $0.similarity)
            },
            tagResults
        )
    }
}

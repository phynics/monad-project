import Foundation
import Logging

/// Error types specific to ContextManager
public enum ContextManagerError: LocalizedError {
    /// Embedding generation failed
    case embeddingFailed(Error)
    /// Database retrieval failed
    case persistenceFailed(Error)
    /// Tag generation failed (non-critical)
    case tagGenerationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .embeddingFailed(let e): return "Embedding failed: \(e.localizedDescription)"
        case .persistenceFailed(let e): return "Database error: \(e.localizedDescription)"
        case .tagGenerationFailed(let e): return "Tag generation failed: \(e.localizedDescription)"
        }
    }
}

/// Manages the retrieval and organization of context for the chat
public actor ContextManager {
    private let persistenceService: any PersistenceServiceProtocol
    private let embeddingService: any EmbeddingService
    private let workspaceRoot: URL?
    private let logger = Logger(label: "com.monad.ContextManager")

    private let learner: ContextLearner
    private let ranker = ContextRanker()

    public init(
        persistenceService: any PersistenceServiceProtocol,
        embeddingService: any EmbeddingService,
        workspaceRoot: URL? = nil
    ) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
        self.workspaceRoot = workspaceRoot
        self.learner = ContextLearner(persistenceService: persistenceService)
    }

    /// Gather all relevant context for a given user query
    /// - Parameters:
    ///   - query: The user's input text
    ///   - history: Recent conversation history to provide context for the search
    ///   - tagGenerator: A function to generate tags from the query (e.g. via LLM)
    /// - Returns: Structured context containing notes and memories
    public func gatherContext(
        for query: String,
        history: [Message] = [],
        limit: Int = 5,
        tagGenerator: (@Sendable (String) async throws -> [String])? = nil,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)? = nil
    ) async throws -> ContextData {
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.debug(
            "Gathering context for query length: \(query.count), history count: \(history.count)")

        onProgress?(.augmenting)
        // Augment query with recent history for better tag generation
        let tagGenerationContext = buildAugmentedContext(query: query, history: history)

        // Parallel execution of tasks
        async let notesTask = fetchAllNotes()
        async let memoriesDataTask = fetchRelevantMemories(
            for: query,
            tagContext: tagGenerationContext,
            limit: limit,
            tagGenerator: tagGenerator,
            onProgress: onProgress
        )

        do {
            let (notes, memoriesData) = try await (notesTask, memoriesDataTask)

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("Context gathered in \(String(format: "%.3f", duration))s")

            onProgress?(.complete)
            return ContextData(
                notes: notes,
                memories: memoriesData.memories,
                generatedTags: memoriesData.tags,
                queryVector: memoriesData.vector,
                augmentedQuery: tagGenerationContext,
                semanticResults: memoriesData.semanticResults,
                tagResults: memoriesData.tagResults,
                executionTime: duration
            )
        } catch {
            logger.error("Context gathering failed: \(error.localizedDescription)")
            throw error
        }
    }

    private func fetchAllNotes() async throws -> [ContextFile] {
        var allNotes: [ContextFile] = []

        // 2. Fetch from Filesystem
        if let workspaceRoot = workspaceRoot {
            let notesDir = workspaceRoot.appendingPathComponent("Notes", isDirectory: true)
            let fileManager = FileManager.default

            if fileManager.fileExists(atPath: notesDir.path) {
                do {
                    let files = try fileManager.contentsOfDirectory(
                        at: notesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

                    for fileURL in files where fileURL.pathExtension == "md" {
                        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                            continue
                        }
                        let name = fileURL.deletingPathExtension().lastPathComponent

                        let note = ContextFile(
                            name: name,
                            content: content,
                            source: "Notes/\(fileURL.lastPathComponent)"
                        )
                        allNotes.append(note)
                    }
                } catch {
                    logger.warning(
                        "Failed to fetch notes from filesystem: \(error.localizedDescription)")
                }
            }
        }

        return allNotes.sorted(by: { $0.name < $1.name })
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
        let embedding: [Double]
        do {
            embedding = try await embeddingService.generateEmbedding(for: query)
        } catch {
            throw ContextManagerError.embeddingFailed(error)
        }

        // Check cancellation
        if Task.isCancelled { return ([], [], [], [], []) }

        // 3. Parallel Retrieval: Vector Search & Tag Search
        onProgress?(.searching)

        let searchTags = tags  // Capture local copy for concurrency safety
        async let semanticTask = persistenceService.searchMemories(
            embedding: embedding,
            limit: limit * 2,  // Search for more to allow for tag-boosted re-ranking
            minSimilarity: 0.35  // Slightly lower to catch more candidates for re-ranking
        )

        async let tagTask = persistenceService.searchMemories(matchingAnyTag: searchTags)

        let (rawSemanticResults, tagResults) = try await (semanticTask, tagTask)
        let semanticResults = rawSemanticResults.map {
            SemanticSearchResult(memory: $0.memory, similarity: $0.similarity)
        }

        // 4. Combine and Rank
        onProgress?(.ranking)

        let finalResults = ranker.rankMemories(
            semantic: semanticResults,
            tagBased: tagResults,
            queryEmbedding: embedding
        )

        // Take top N based on limit
        let topResults = Array(finalResults.prefix(limit))

        logger.info(
            "Recall performance: \(topResults.count) memories selected from \(semanticResults.count) semantic + \(tagResults.count) tag matches"
        )

        return (
            topResults,
            tags,
            embedding,
            semanticResults.map {
                SemanticSearchResult(memory: $0.memory, similarity: $0.similarity)
            },
            tagResults
        )
    }

    /// Adjust memory embeddings based on helpfulness scores
    /// - Parameters:
    ///   - evaluations: Dictionary of memory ID to helpfulness score (-1.0 to 1.0)
    ///   - queryVectors: The vectors of the queries that triggered these recalls
    public func adjustEmbeddings(
        evaluations: [String: Double],
        queryVectors: [[Double]]
    ) async throws {
        try await learner.adjustEmbeddings(evaluations: evaluations, queryVectors: queryVectors)
    }
}

/// Structured context data
public struct ContextData: Sendable {
    public let notes: [ContextFile]
    public let memories: [SemanticSearchResult]
    public let generatedTags: [String]
    public let queryVector: [Double]
    public let augmentedQuery: String?
    public let semanticResults: [SemanticSearchResult]
    public let tagResults: [Memory]
    public let executionTime: TimeInterval

    public init(
        notes: [ContextFile] = [],
        memories: [SemanticSearchResult] = [],
        generatedTags: [String] = [],
        queryVector: [Double] = [],
        augmentedQuery: String? = nil,
        semanticResults: [SemanticSearchResult] = [],
        tagResults: [Memory] = [],
        executionTime: TimeInterval = 0
    ) {
        self.notes = notes
        self.memories = memories
        self.generatedTags = generatedTags
        self.queryVector = queryVector
        self.augmentedQuery = augmentedQuery
        self.semanticResults = semanticResults
        self.tagResults = tagResults
        self.executionTime = executionTime
    }
}

import Dependencies
import ErrorKit
import Foundation
import Logging
import MonadShared

// MARK: - Memory Retrieval

extension ContextManager {
    func fetchRelevantMemories(
        for query: String,
        tagContext: String,
        limit: Int,
        tagGenerator: (@Sendable (String) async throws -> [String])?,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)?
    ) async throws -> MemoryRetrievalResult {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return MemoryRetrievalResult(memories: [], tags: [], vector: [], semanticResults: [], tagResults: [])
        }

        let tags = await generateTagsSafely(tagContext: tagContext, tagGenerator: tagGenerator, onProgress: onProgress)
        let embedding = try await generateQueryEmbedding(for: query, onProgress: onProgress)

        if Task.isCancelled {
            return MemoryRetrievalResult(memories: [], tags: [], vector: [], semanticResults: [], tagResults: [])
        }

        let doubleEmbedding = embedding.map { Double($0) }
        let (semanticResults, tagResults) = try await performParallelSearch(
            embedding: doubleEmbedding, tags: tags, limit: limit, onProgress: onProgress
        )

        onProgress?(.ranking)
        let finalResults = ranker.rankMemories(
            semantic: semanticResults, tagBased: tagResults, queryEmbedding: doubleEmbedding
        )
        let topResults = Array(finalResults.prefix(limit))

        // swiftlint:disable:next line_length
        logger.info("Recall: \(topResults.count) memories selected from \(semanticResults.count) semantic + \(tagResults.count) tag matches")

        return MemoryRetrievalResult(
            memories: topResults, tags: tags, vector: doubleEmbedding,
            semanticResults: semanticResults, tagResults: tagResults
        )
    }

    // MARK: - Helpers

    private func generateTagsSafely(
        tagContext: String,
        tagGenerator: (@Sendable (String) async throws -> [String])?,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)?
    ) async -> [String] {
        guard let generator = tagGenerator else { return [] }
        onProgress?(.tagging)
        do {
            let tags = try await generator(tagContext)
            logger.debug("Generated tags: \(tags)")
            return tags
        } catch {
            logger.warning("Optional tag generation failed: \(ErrorKit.userFriendlyMessage(for: error))")
            return []
        }
    }

    private func generateQueryEmbedding(
        for query: String,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)?
    ) async throws -> [Float] {
        onProgress?(.embedding)
        do {
            return try await embeddingService.generateEmbedding(for: query)
        } catch {
            throw ContextManagerError.embeddingFailed(error)
        }
    }

    private func performParallelSearch(
        embedding: [Double],
        tags: [String],
        limit: Int,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)?
    ) async throws -> ([SemanticSearchResult], [Memory]) {
        onProgress?(.searching)

        async let semanticTask = memoryStore.searchMemories(
            embedding: embedding,
            limit: limit * 2,
            minSimilarity: 0.35
        )
        async let tagTask = memoryStore.searchMemories(matchingAnyTag: tags)

        let (rawSemanticResults, tagResults) = try await (semanticTask, tagTask)
        let semanticResults = rawSemanticResults.map {
            SemanticSearchResult(memory: $0.memory, similarity: $0.similarity)
        }
        return (semanticResults, tagResults)
    }
}

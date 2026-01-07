import Foundation
import OSLog

/// Manages the retrieval and organization of context for the chat
public actor ContextManager {
    private let persistenceService: PersistenceService
    private let embeddingService: any EmbeddingService
    private let logger = Logger(subsystem: "com.monad.core", category: "ContextManager")

    public init(persistenceService: PersistenceService, embeddingService: any EmbeddingService) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
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
        tagGenerator: (@Sendable (String) async throws -> [String])? = nil,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)? = nil
    ) async throws -> ContextData {
        logger.debug("Gathering context for query length: \(query.count), history count: \(history.count)")
        
        onProgress?(.augmenting)
        // Augment query with recent history for better semantic search in multi-turn conversations
        let augmentedQuery: String
        if !history.isEmpty {
            // Take the last few user messages to provide context
            let historyContext = history
                .filter { $0.role == .user }
                .suffix(2)
                .map { $0.content }
                .joined(separator: " ")
            
            if !historyContext.isEmpty {
                augmentedQuery = "\(historyContext) \(query)"
                logger.debug("Augmented query for search: \(augmentedQuery)")
            } else {
                augmentedQuery = query
            }
        } else {
            augmentedQuery = query
        }
        
        async let notesTask = persistenceService.fetchAlwaysAppendNotes()
        async let memoriesDataTask = fetchRelevantMemories(for: augmentedQuery, tagGenerator: tagGenerator, onProgress: onProgress)
        
        let (notes, memoriesData) = try await (notesTask, memoriesDataTask)
        
        onProgress?(.complete)
        return ContextData(
            notes: notes,
            memories: memoriesData.memories,
            generatedTags: memoriesData.tags,
            queryVector: memoriesData.vector,
            augmentedQuery: augmentedQuery,
            semanticResults: memoriesData.semanticResults,
            tagResults: memoriesData.tagResults
        )
    }
    
    private func fetchRelevantMemories(
        for query: String,
        tagGenerator: (@Sendable (String) async throws -> [String])?,
        onProgress: (@Sendable (Message.ContextGatheringProgress) -> Void)?
    ) async throws -> (
        memories: [SemanticSearchResult], 
        tags: [String], 
        vector: [Double],
        semanticResults: [SemanticSearchResult],
        tagResults: [Memory]
    ) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ([], [], [], [], [])
        }
        
        // 1. Generate Tags (if generator provided)
        var tags: [String] = []
        if let generator = tagGenerator {
            onProgress?(.tagging)
            // We run this concurrently with embedding if possible, but inside this actor we await.
            // Tag generation might be slow (LLM call), so ideally we'd run parallel.
            // But we need tags for the search.
            // Let's run embedding and tag generation in parallel.
            tags = try await generator(query)
            logger.debug("Generated tags: \(tags)")
        }
        
        // 2. Generate Embedding
        onProgress?(.embedding)
        let embedding = try await embeddingService.generateEmbedding(for: query)
        
        // 3. Search using Vector (Semantic) - Top 5 candidates
        onProgress?(.searching)
        let semanticResults = try await persistenceService.searchMemories(
            embedding: embedding,
            limit: 5,
            minSimilarity: 0.4 // Lowered threshold since we re-rank later
        )
        
        // 4. Search using Tags (Keyword)
        let tagResults = try await persistenceService.searchMemories(matchingAnyTag: tags)
        
        // 5. Combine and Rank
        onProgress?(.ranking)
        // We need to calculate similarity for tag-based results that weren't in semantic results
        
        var finalResults: [SemanticSearchResult] = semanticResults.map { 
            SemanticSearchResult(memory: $0.memory, similarity: $0.similarity)
        }
        
        let existingIds = Set(finalResults.map { $0.memory.id })
        
        for memory in tagResults {
            if !existingIds.contains(memory.id) {
                // Calculate similarity manually
                let sim = cosineSimilarity(embedding, memory.embeddingVector)
                finalResults.append(SemanticSearchResult(memory: memory, similarity: sim))
            }
        }
        
        // Sort by similarity descending
        finalResults.sort { ($0.similarity ?? 0) > ($1.similarity ?? 0) }
        
        // Take top 3
        let topResults = Array(finalResults.prefix(3))
        
        logger.info("Found \(topResults.count) relevant memories (from \(semanticResults.count) semantic + \(tagResults.count) tag matches)")
        
        return (topResults, tags, embedding, semanticResults.map { SemanticSearchResult(memory: $0.memory, similarity: $0.similarity) }, tagResults)
    }
    
    // Helper for cosine similarity (duplicated from PersistenceService, could be shared utility)
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dot = 0.0
        var magA = 0.0
        var magB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        return dot / (sqrt(magA) * sqrt(magB))
    }

    /// Adjust memory embeddings based on helpfulness scores
    /// - Parameters:
    ///   - evaluations: Dictionary of memory ID to helpfulness score (-1.0 to 1.0)
    ///   - queryVectors: The vectors of the queries that triggered these recalls
    public func adjustEmbeddings(
        evaluations: [String: Double],
        queryVectors: [[Double]]
    ) async throws {
        guard !evaluations.isEmpty, !queryVectors.isEmpty else { return }
        
        let learningRate = 0.05 // Small step size
        
        for (idString, score) in evaluations {
            guard let id = UUID(uuidString: idString), score != 0 else { continue }
            
            // Fetch current memory
            guard let memory = try await persistenceService.fetchMemory(id: id) else { continue }
            let currentVector = memory.embeddingVector
            guard !currentVector.isEmpty else { continue }
            
            // Average the query vectors that might have triggered this (simplified)
            // Ideally we'd map specific turns to specific memories, but for now we'll push/pull 
            // relative to all queries in the session if the memory was recalled.
            
            var targetVector = [Double](repeating: 0, count: currentVector.count)
            for qv in queryVectors {
                guard qv.count == currentVector.count else { continue }
                for i in 0..<currentVector.count {
                    targetVector[i] += qv[i]
                }
            }
            
            // Normalize averaged target
            targetVector = normalize(targetVector)
            
            // Calculate adjustment
            // V' = V + score * learningRate * (Target - V)
            var newVector = currentVector
            for i in 0..<currentVector.count {
                let delta = targetVector[i] - currentVector[i]
                newVector[i] += score * learningRate * delta
            }
            
            // Re-normalize to keep on unit hypersphere
            newVector = normalize(newVector)
            
            // Save back
            try await persistenceService.updateMemoryEmbedding(id: id, newEmbedding: newVector)
            logger.info("Adjusted embedding for memory '\(memory.title)' with score \(score)")
        }
    }
    
    private func normalize(_ v: [Double]) -> [Double] {
        let mag = sqrt(v.reduce(0) { $0 + $1 * $1 })
        guard mag > 0 else { return v }
        return v.map { $0 / mag }
    }
}

/// Structured context data
public struct ContextData: Sendable {
    public let notes: [Note]
    public let memories: [SemanticSearchResult]
    public let generatedTags: [String]
    public let queryVector: [Double]
    public let augmentedQuery: String?
    public let semanticResults: [SemanticSearchResult]
    public let tagResults: [Memory]
    
    public init(
        notes: [Note] = [],
        memories: [SemanticSearchResult] = [],
        generatedTags: [String] = [],
        queryVector: [Double] = [],
        augmentedQuery: String? = nil,
        semanticResults: [SemanticSearchResult] = [],
        tagResults: [Memory] = []
    ) {
        self.notes = notes
        self.memories = memories
        self.generatedTags = generatedTags
        self.queryVector = queryVector
        self.augmentedQuery = augmentedQuery
        self.semanticResults = semanticResults
        self.tagResults = tagResults
    }
}

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
    /// - Parameter query: The user's input text
    /// - Returns: Structured context containing notes and memories
    public func gatherContext(for query: String) async throws -> ContextData {
        logger.debug("Gathering context for query length: \(query.count)")
        
        async let notesTask = persistenceService.fetchAlwaysAppendNotes()
        async let memoriesTask = fetchRelevantMemories(for: query)
        
        let (notes, memories) = try await (notesTask, memoriesTask)
        
        return ContextData(notes: notes, memories: memories)
    }
    
    private func fetchRelevantMemories(for query: String) async throws -> [SemanticSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        // Generate embedding for query
        let embedding = try await embeddingService.generateEmbedding(for: query)
        
        // Search semantically (min similarity 0.7)
        let semanticResults = try await persistenceService.searchMemories(
            embedding: embedding,
            limit: 5,
            minSimilarity: 0.7
        )
        
        // Also do a simple keyword search for tags/title
        let keywordResults = try await persistenceService.searchMemories(query: query)
        
        // Combine results, prioritizing semantic ones and removing duplicates
        var all = semanticResults.map { SemanticSearchResult(memory: $0.memory, similarity: $0.similarity) }
        let existingIds = Set(all.map { $0.memory.id })
        
        for mem in keywordResults {
            if !existingIds.contains(mem.id) {
                all.append(SemanticSearchResult(memory: mem, similarity: nil))
            }
        }
        
        logger.info("Found \(all.count) relevant memories for query")
        return all
    }
}

/// Structured context data
public struct ContextData: Sendable {
    public let notes: [Note]
    public let memories: [SemanticSearchResult]
    
    public init(notes: [Note] = [], memories: [SemanticSearchResult] = []) {
        self.notes = notes
        self.memories = memories
    }
}

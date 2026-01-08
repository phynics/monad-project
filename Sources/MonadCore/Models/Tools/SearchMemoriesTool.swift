import Foundation

/// Tool to search memories
public class SearchMemoriesTool: Tool, @unchecked Sendable {
    public let id = "search_memories"
    public let name = "Search Memories"
    public let description = "Search through stored memories to find relevant information"
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "search_memories", "arguments": {"query": "deployment"}}
        </tool_call>
        """
    }
    
    private let persistenceService: PersistenceService
    private let embeddingService: any EmbeddingService
    
    public init(persistenceService: PersistenceService, embeddingService: any EmbeddingService) {
        self.persistenceService = persistenceService
        self.embeddingService = embeddingService
    }
    
    public func canExecute() async -> Bool {
        return true
    }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search query to find in memories (searches title and content)"
                ],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional list of tags to filter by"
                ]
            ]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let query = parameters["query"] as? String
        let tags = parameters["tags"] as? [String]
        
        if query == nil && (tags == nil || tags!.isEmpty) {
            return .failure("Either 'query' or 'tags' must be provided.")
        }
        
        do {
            var allMemories: [Memory] = []
            
            if let query = query, !query.isEmpty {
                // 1. Keyword search
                let keywordMemories = try await persistenceService.searchMemories(query: query)
                
                // 2. Semantic search
                let embedding = try await embeddingService.generateEmbedding(for: query)
                let semanticResults = try await persistenceService.searchMemories(embedding: embedding, limit: 5, minSimilarity: 0.4)
                
                // Combine results, avoiding duplicates
                allMemories = keywordMemories
                let keywordIds = Set(allMemories.map { $0.id })
                
                for result in semanticResults {
                    if !keywordIds.contains(result.memory.id) {
                        allMemories.append(result.memory)
                    }
                }
            }
            
            if let tags = tags, !tags.isEmpty {
                let tagMemories = try await persistenceService.searchMemories(matchingAnyTag: tags)
                let existingIds = Set(allMemories.map { $0.id })
                for memory in tagMemories {
                    if !existingIds.contains(memory.id) {
                        allMemories.append(memory)
                    }
                }
            }

            if allMemories.isEmpty {
                let criteria = [query != nil ? "query '\(query!)'" : nil, tags != nil ? "tags \(tags!)" : nil]
                    .compactMap { $0 }.joined(separator: " and ")
                return .success("No memories found matching \(criteria)")
            }

            let formattedResults = allMemories.map { $0.promptString }.joined(separator: "\n\n---\n\n")
            return .success("Found \(allMemories.count) memories:\n\n\(formattedResults)")
        } catch {
            return .failure("Search failed: \(error.localizedDescription)")
        }
    }
}

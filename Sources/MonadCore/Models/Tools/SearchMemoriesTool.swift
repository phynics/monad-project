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
                    "description": "Search query to find in memories"
                ]
            ],
            "required": ["query"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let query = parameters["query"] as? String else {
            let errorMsg = "Missing required parameter: query."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }
        
        do {
            // 1. Keyword search
            let keywordMemories = try await persistenceService.searchMemories(query: query)
            
            // 2. Semantic search
            let embedding = try await embeddingService.generateEmbedding(for: query)
            let semanticResults = try await persistenceService.searchMemories(embedding: embedding, limit: 5, minSimilarity: 0.4)
            
            // Combine results, avoiding duplicates
            var allMemories = keywordMemories
            let keywordIds = Set(allMemories.map { $0.id })
            
            for result in semanticResults {
                if !keywordIds.contains(result.memory.id) {
                    allMemories.append(result.memory)
                }
            }

            if allMemories.isEmpty {
                return .success("No memories found matching '\(query)'")
            }

            let formattedResults = allMemories.map { $0.promptString }.joined(separator: "\n\n---\n\n")
            return .success("Found \(allMemories.count) memories for '\(query)':\n\n\(formattedResults)")
        } catch {
            return .failure("Search failed: \(error.localizedDescription)")
        }
    }
}

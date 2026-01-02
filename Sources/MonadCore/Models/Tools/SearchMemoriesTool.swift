import Foundation

/// Tool to search memories
public class SearchMemoriesTool: Tool, @unchecked Sendable {
    public let id = "search_memories"
    public let name = "Search Memories"
    public let description = "Search through stored memories to find relevant information"
    public let requiresPermission = false
    
    private let persistenceService: PersistenceService
    
    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
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
            return .failure("Missing required parameter: query")
        }
        
        do {
            let memories = try await persistenceService.searchMemories(query: query)

            if memories.isEmpty {
                return .success("No memories found matching '\(query)'")
            }

            let formattedResults = memories.map { $0.promptString }.joined(separator: "\n\n---\n\n")
            return .success("Found \(memories.count) memories for '\(query)':\n\n\(formattedResults)")
        } catch {
            return .failure("Search failed: \(error.localizedDescription)")
        }
    }
}

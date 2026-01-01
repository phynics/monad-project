import Foundation

/// Tool to search memories
class SearchMemoriesTool: Tool, @unchecked Sendable {
    let id = "search_memories"
    let name = "Search Memories"
    let description = "Search through stored memories to find relevant information"
    let requiresPermission = false
    
    private let persistenceManager: PersistenceManager
    
    init(persistenceManager: PersistenceManager) {
        self.persistenceManager = persistenceManager
    }
    
    func canExecute() async -> Bool {
        return true
    }
    
    var parametersSchema: [String: Any] {
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
    
    func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let query = parameters["query"] as? String else {
            return .failure("Missing required parameter: query")
        }
        
        do {
            let memories = try await persistenceManager.searchMemories(query: query)

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

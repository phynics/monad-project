import Foundation

/// Tool to search archived conversations
class SearchArchivedChatsTool: Tool, @unchecked Sendable {
    let id = "search_archived_chats"
    let name = "Search Archived Chats"
    let description = "Search through archived conversation history to find past discussions"
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
                    "description": "Search query to find in archived conversations"
                ]
            ],
            "required": ["query"]
        ]
    }
    
    func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let query = parameters["query"] as? String else {
            return .failure("Missing required parameter: query")
        }
        
        let sessions = try await persistenceManager.searchArchivedSessions(query: query)
        
        if sessions.isEmpty {
            return .success("No archived conversations found matching '\(query)'")
        }
        
        let results = sessions.prefix(5).map { session in
            "- \(session.title) (Updated: \(session.updatedAt.formatted()))"
        }.joined(separator: "\n")
        
        return .success("Found \(sessions.count) archived conversation(s):\n\(results)")
    }
}

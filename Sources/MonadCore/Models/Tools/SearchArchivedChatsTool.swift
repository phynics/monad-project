import Foundation

/// Tool to search archived conversations
public class SearchArchivedChatsTool: Tool, @unchecked Sendable {
    public let id = "search_archived_chats"
    public let name = "Search Archived Chats"
    public let description = "Search through archived conversation history to find past discussions"
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "search_archived_chats", "arguments": {"query": "SwiftUI architecture"}}
        </tool_call>
        """
    }
    
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
                    "description": "Search query to find in archived conversations"
                ]
            ],
            "required": ["query"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let query = parameters["query"] as? String else {
            return .failure("Missing required parameter: query")
        }
        
        let sessions = try await persistenceService.searchArchivedSessions(query: query)
        
        if sessions.isEmpty {
            return .success("No archived conversations found matching '\(query)'")
        }
        
        let results: String = sessions.prefix(5).map { session in
            "- \(session.title) (Updated: \(session.updatedAt.formatted()))"
        }.joined(separator: "\n")
        
        return .success("Found \(sessions.count) archived conversation(s):\n\(results)")
    }
}

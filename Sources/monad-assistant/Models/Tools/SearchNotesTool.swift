import Foundation

/// Tool to search context notes
class SearchNotesTool: Tool, @unchecked Sendable {
    let id = "search_notes"
    let name = "Search Notes"
    let description = "Search through context notes to find relevant information"
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
                    "description": "Search query to find in notes"
                ]
            ],
            "required": ["query"]
        ]
    }
    
    func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let query = parameters["query"] as? String else {
            return .failure("Missing required parameter: query")
        }
        
        let notes = try await persistenceManager.searchNotes(query: query)
        
        if notes.isEmpty {
            return .success("No notes found matching '\(query)'")
        }
        
        let results = notes.prefix(5).map { note in
            let readonly = note.isReadonly ? " [READONLY]" : ""
            return "- \(note.name)\(readonly): \(note.description)"
        }.joined(separator: "\n")
        
        return .success("Found \(notes.count) note(s):\n\(results)")
    }
}

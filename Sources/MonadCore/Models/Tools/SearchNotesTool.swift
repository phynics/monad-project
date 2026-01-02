import Foundation

/// Tool to search context notes
public class SearchNotesTool: Tool, @unchecked Sendable {
    public let id = "search_notes"
    public let name = "Search Notes"
    public let description = "Search through context notes to find relevant information"
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
                    "description": "Search query to find in notes"
                ]
            ],
            "required": ["query"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let query = parameters["query"] as? String else {
            return .failure("Missing required parameter: query")
        }
        
        let notes = try await persistenceService.searchNotes(query: query)
        
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

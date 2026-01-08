import Foundation

/// Tool to search context notes
public struct SearchNotesTool: Tool, @unchecked Sendable {
    public let id = "search_notes"
    public let name = "Search Notes"
    public let description = "Search through context notes to find relevant information"
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "search_notes", "arguments": {"query": "coding standards"}}
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
                    "description": "Search query to find in notes (searches name, description, and content)"
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
            var allNotes: [Note] = []
            
            if let query = query, !query.isEmpty {
                allNotes = try await persistenceService.searchNotes(query: query)
            }
            
            if let tags = tags, !tags.isEmpty {
                let tagNotes = try await persistenceService.searchNotes(matchingAnyTag: tags)
                let existingIds = Set(allNotes.map { $0.id })
                for note in tagNotes {
                    if !existingIds.contains(note.id) {
                        allNotes.append(note)
                    }
                }
            }

            if allNotes.isEmpty {
                let criteria = [query != nil ? "query '\(query!)'" : nil, tags != nil ? "tags \(tags!)" : nil]
                    .compactMap { $0 }.joined(separator: " and ")
                return .success("No notes found matching \(criteria)")
            }
            
            let results: String = allNotes.prefix(10).map { note in
                let readonly = note.isReadonly ? " [READONLY]" : ""
                let tagsStr = note.tagArray.isEmpty ? "" : " [Tags: \(note.tagArray.joined(separator: ", "))]"
                return "- \(note.name)\(readonly)\(tagsStr): \(note.description)"
            }.joined(separator: "\n")
            
            return .success("Found \(allNotes.count) note(s):\n\(results)")
        } catch {
            return .failure("Search failed: \(error.localizedDescription)")
        }
    }
}

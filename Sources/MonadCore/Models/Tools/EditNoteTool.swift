import Foundation

/// Tool to edit a context note (only if not readonly)
public class EditNoteTool: Tool, @unchecked Sendable {
    public let id = "edit_note"
    public let name = "Edit Note"
    public let description = "Edit a context note's content (only non-readonly notes)"
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
                "note_name": [
                    "type": "string",
                    "description": "Name of the note to edit"
                ],
                "content": [
                    "type": "string",
                    "description": "New content for the note"
                ],
                "description": [
                    "type": "string",
                    "description": "Optional new description for the note"
                ]
            ],
            "required": ["note_name", "content"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let noteName = parameters["note_name"] as? String,
              let newContent = parameters["content"] as? String else {
            return .failure("Missing required parameters: note_name and content")
        }
        
        // Search for note by name
        let notes = try await persistenceService.searchNotes(query: noteName)
        guard let note = notes.first(where: { $0.name == noteName }) else {
            return .failure("Note '\(noteName)' not found")
        }
        
        // Check if readonly
        if note.isReadonly {
            return .failure("Cannot edit readonly note '\(noteName)'")
        }
        
        // Update note
        var updatedNote = note
        updatedNote.content = newContent
        if let newDescription = parameters["description"] as? String {
            updatedNote.description = newDescription
        }
        updatedNote.updatedAt = Date()
        
        try await persistenceService.saveNote(updatedNote)
        
        return .success("Note '\(noteName)' updated successfully")
    }
}

import Foundation

/// Tool to edit a context note (only if not readonly)
public class EditNoteTool: Tool, @unchecked Sendable {
    public let id = "edit_note"
    public let name = "Edit Note"
    public let description = "Edit a context note's content"
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "edit_note", "arguments": {"note_name": "Project Guidelines", "content": "- New rule", "line_index": -1, "mode": "append"}}
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
                ],
                "line_index": [
                    "type": "integer",
                    "description": "Line number to replace (0-indexed). Use -1 to append. If provided, performs line-based edit."
                ],
                "mode": [
                    "type": "string",
                    "enum": ["overwrite", "append", "replace_line"],
                    "description": "Explicit edit mode. 'overwrite' replaces entire content. 'append' adds to end. 'replace_line' requires line_index."
                ]
            ],
            "required": ["note_name", "content"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let noteName = parameters["note_name"] as? String,
              let newContent = parameters["content"] as? String else {
            let errorMsg = "Missing required parameters: note_name and content."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }
        
        // Search for note by name
        let notes = try await persistenceService.searchNotes(query: noteName)
        guard let note = notes.first(where: { $0.name == noteName }) else {
            return .failure("Note '\(noteName)' not found")
        }
        
        // Update note
        var updatedNote = note
        var finalContent = newContent
        
        // Determine mode and perform edit
        let lineIndex = parameters["line_index"] as? Int
        let mode = parameters["mode"] as? String
        
        if let idx = lineIndex {
            // Line based operation
            var lines = updatedNote.content.components(separatedBy: .newlines)
            
            if idx == -1 || mode == "append" {
                // Deduplicate: Don't append if the last line is identical
                if lines.last != newContent {
                    lines.append(newContent)
                }
            } else if idx >= 0 && idx < lines.count {
                lines[idx] = newContent
            } else {
                return .failure("Invalid line_index: \(idx). Note has \(lines.count) lines.")
            }
            
            finalContent = lines.joined(separator: "\n")
        } else if mode == "append" {
            // Append without line index
            // Deduplicate: Check if content already ends with new content
            if !updatedNote.content.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(newContent.trimmingCharacters(in: .whitespacesAndNewlines)) {
                finalContent = updatedNote.content + "\n" + newContent
            } else {
                finalContent = updatedNote.content
            }
        } else {
            // Default: Overwrite
            finalContent = newContent
        }
        
        updatedNote.content = finalContent
        
        if let newDescription = parameters["description"] as? String {
            updatedNote.description = newDescription
        }
        updatedNote.updatedAt = Date()
        
        try await persistenceService.saveNote(updatedNote)
        
        return .success("Note '\(noteName)' updated successfully")
    }
}

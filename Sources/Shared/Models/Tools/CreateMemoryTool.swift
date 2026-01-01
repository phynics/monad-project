import Foundation

/// Tool to create a new memory
class CreateMemoryTool: Tool, @unchecked Sendable {
    let id = "create_memory"
    let name = "Create Memory"
    let description = "Create a new memory entry to remember important information"
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
                "title": [
                    "type": "string",
                    "description": "Title of the memory"
                ],
                "content": [
                    "type": "string",
                    "description": "Content to remember"
                ],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional tags for categorization"
                ]
            ],
            "required": ["title", "content"]
        ]
    }
    
    func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let title = parameters["title"] as? String,
              let content = parameters["content"] as? String else {
            return .failure("Missing required parameters: title and content")
        }
        
        // TODO: Implement memory creation when memory system is ready
        return .success("Memory '\(title)' created - Feature coming soon")
    }
}

import Foundation

/// Tool to move the excerpt window
public struct MoveDocumentExcerptTool: Tool, @unchecked Sendable {
    public let id = "move_document_excerpt"
    public let name = "Move Document Excerpt"
    public let description = "Move the visible window of a document excerpt"
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "move_document_excerpt", "arguments": {"path": "README.md", "offset": 500}}
        </tool_call>
        """
    }
    
    private let documentManager: DocumentManager
    
    public init(documentManager: DocumentManager) {
        self.documentManager = documentManager
    }
    
    public func canExecute() async -> Bool {
        return true
    }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "Path to the loaded document"
                ],
                "offset": [
                    "type": "integer",
                    "description": "New start character offset"
                ]
            ],
            "required": ["path", "offset"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let path = parameters["path"] as? String,
              let offset = parameters["offset"] as? Int else {
            let errorMsg = "Missing required parameters: path and offset."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }
        
        guard var doc = await documentManager.getDocument(path: path) else {
            return .failure("Document not found in context: \(path)")
        }
        
        doc.excerptOffset = max(0, offset)
        doc.viewMode = .excerpt
        
        await documentManager.updateDocument(doc)
        return .success("Moved excerpt to offset \(offset). Visible content updated.")
    }
}

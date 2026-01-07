import Foundation

/// Tool to load a document into context
public struct LoadDocumentTool: Tool, @unchecked Sendable {
    public let id = "load_document"
    public let name = "Load Document"
    public let description = "Load a text document into the active context"
    public let requiresPermission = true
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "load_document", "arguments": {"path": "README.md"}}
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
                    "description": "Path to the document to load"
                ],
                "force_full": [
                    "type": "boolean",
                    "description": "Force load full content even if large (default: false)"
                ]
            ],
            "required": ["path"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let path = parameters["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        
        let forceFull = parameters["force_full"] as? Bool ?? false
        let url = URL(fileURLWithPath: path).standardized
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Check size
            var mode: DocumentContext.ViewMode = .full
            var message = "Document loaded successfully."
            
            if content.count > 5000 && !forceFull {
                mode = .excerpt
                message = "Document loaded. File is large (\(content.count) chars), so it was loaded in 'excerpt' view. You can use 'move_excerpt' to read different parts, or 'load_document' with 'force_full: true' to load everything (use with caution)."
            }
            
            await documentManager.loadDocument(path: path, content: content)
            
            if var doc = await documentManager.getDocument(path: path) {
                doc.viewMode = mode
                await documentManager.updateDocument(doc)
            }
            
            return .success(message)
        } catch {
            return .failure("Failed to load document: \(error.localizedDescription)")
        }
    }
}

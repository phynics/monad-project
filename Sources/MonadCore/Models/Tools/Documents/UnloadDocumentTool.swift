import Foundation

/// Tool to unload a document from context
public struct UnloadDocumentTool: Tool, Sendable {
    public let id = "unload_document"
    public let name = "Unload Document"
    public let description = "Remove a document from the active context"
    public let requiresPermission = false

    public var usageExample: String? {
        """
        <tool_call>
        {"name": "unload_document", "arguments": {"path": "README.md"}}
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
                    "description": "Path to the document to unload",
                ]
            ],
            "required": ["path"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let path = parameters["path"] as? String else {
            let errorMsg = "Missing required parameter: path."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }

        await documentManager.unloadDocument(path: path)
        return .success("Document unloaded: \(path)")
    }
}

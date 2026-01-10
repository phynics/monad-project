import Foundation

/// Tool to switch view mode for a document
public struct SwitchDocumentViewTool: Tool, Sendable {
    public let id = "switch_document_view"
    public let name = "Switch Document View"
    public let description = "Change the view mode of a loaded document (full, excerpt, or summary)"
    public let requiresPermission = false

    public var usageExample: String? {
        """
        <tool_call>
        {"name": "switch_document_view", "arguments": {"path": "README.md", "view": "summary"}}
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
                    "description": "Path to the loaded document",
                ],
                "view": [
                    "type": "string",
                    "enum": ["raw", "excerpt", "summary", "metadata"],
                    "description":
                        "The view mode to switch to (raw, excerpt, summary, or metadata)",
                ],
            ],
            "required": ["path", "view"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let path = parameters["path"] as? String,
            let viewString = parameters["view"] as? String,
            let view = DocumentContext.ViewMode(rawValue: viewString)
        else {
            let errorMsg =
                "Missing or invalid parameters. 'view' must be one of: raw, excerpt, summary, metadata."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }

        guard var doc = await documentManager.getDocument(path: path) else {
            return .failure("Document not found in context: \(path)")
        }

        doc.viewMode = view
        await documentManager.updateDocument(doc)
        return .success("Switched \(path) to \(viewString) view.")
    }
}

import Foundation

/// Tool to load a document into context
public struct LoadDocumentTool: Tool, Sendable {
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
                    "description": "Path to the document to load",
                ],
                "force_full": [
                    "type": "boolean",
                    "description": "Force load full content even if large (default: false)",
                ],
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

        let url = URL(fileURLWithPath: path).standardized
        let targetPath = url.path

        do {
            let content = try String(contentsOf: url, encoding: .utf8)

            // Always default to metadata mode on initial load to save context
            let mode: DocumentContext.ViewMode = .metadata
            let message =
                "Document '\(targetPath)' loaded into context in 'metadata' mode. Use `switch_document_view` to read content."

            await documentManager.loadDocument(path: targetPath, content: content)

            if var doc = await documentManager.getDocument(path: targetPath) {
                doc.viewMode = mode
                await documentManager.updateDocument(doc)
            }

            return .success(message)
        } catch {
            return .failure("Failed to load document: \(error.localizedDescription)")
        }
    }
}

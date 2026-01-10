import Foundation

/// Tool to edit a document's summary
public struct EditDocumentSummaryTool: Tool, Sendable {
    public let id = "edit_document_summary"
    public let name = "Edit Document Summary"
    public let description =
        "Edit the summary or notes for a loaded document. Useful for tracking analysis or intent."
    public let requiresPermission = false

    public var usageExample: String? {
        """
        <tool_call>
        {"name": "edit_document_summary", "arguments": {"path": "Sources/Main.swift", "summary": "Main entry point. Needs refactoring."}}
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
                "summary": [
                    "type": "string",
                    "description": "The new summary text",
                ],
            ],
            "required": ["path", "summary"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let path = parameters["path"] as? String,
            let summary = parameters["summary"] as? String
        else {
            let errorMsg = "Missing required parameters: path and summary."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }

        guard var doc = await documentManager.getDocument(path: path) else {
            return .failure("Document not found in context: \(path)")
        }

        doc.summary = summary

        // Auto-switch to summary view if not already, to confirm the change visually?
        // No, let the model decide view mode. Just update the data.

        await documentManager.updateDocument(doc)
        return .success("Updated summary for \(path)")
    }
}

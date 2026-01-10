import Foundation

/// Tool to load an archived conversation as a document
public struct LoadArchivedChatTool: Tool, Sendable {
    public let id = "load_archived_chat"
    public let name = "Load Archived Chat"
    public let description =
        "Load an archived conversation transcript into the active context as a document"
    public let requiresPermission = false

    public var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"load_archived_chat\", \"arguments\": {\"session_id\": \"UUID-HERE\"}}
        </tool_call>
        """
    }

    private let persistenceService: PersistenceService
    private let documentManager: DocumentManager

    public init(persistenceService: PersistenceService, documentManager: DocumentManager) {
        self.persistenceService = persistenceService
        self.documentManager = documentManager
    }

    public func canExecute() async -> Bool {
        return true
    }

    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "session_id": [
                    "type": "string",
                    "description": "The UUID of the archived conversation to load",
                ]
            ],
            "required": ["session_id"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let idString = parameters["session_id"] as? String,
            let sessionId = UUID(uuidString: idString)
        else {
            return .failure("Invalid or missing session_id.")
        }

        do {
            guard let session = try await persistenceService.fetchSession(id: sessionId) else {
                return .failure("Archived conversation not found.")
            }

            let messages = try await persistenceService.fetchMessages(for: sessionId)

            if messages.isEmpty {
                return .success("The archived conversation '\(session.title)' is empty.")
            }

            let transcript = messages.map { msg -> String in
                let role = msg.role.uppercased()
                let time = msg.timestamp.formatted(date: .omitted, time: .shortened)
                return "[\(time)] [\(role)]: \(msg.content)"
            }.joined(separator: "\n\n")

            let path = "archived://\(sessionId.uuidString)"
            let content = """
                TITLE: \(session.title)
                DATE: \(session.createdAt.formatted())

                TRANSCRIPT:
                \(transcript)
                """

            await documentManager.loadDocument(path: path, content: content)

            return .success(
                "Archived conversation '\(session.title)' loaded as document '\(path)'. You can now use document tools to read it."
            )

        } catch {
            return .failure("Failed to load archived chat: \(error.localizedDescription)")
        }
    }
}

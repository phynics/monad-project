import Foundation

/// Tool to view chat history from persistence
public struct ViewChatHistoryTool: Tool, @unchecked Sendable {
    public let id = "view_chat_history"
    public let name = "View Chat History"
    public let description = "Fetch past messages from the current or a specific conversation session. Use this if the prompt history has been truncated."
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"view_chat_history\", \"arguments\": {\"session_id\": \"optional-uuid\", \"limit\": 20, \"offset\": 0}}
        </tool_call>
        """
    }
    
    private let persistenceService: PersistenceService
    // We need a way to know the current session ID. 
    // Since Tool is stateless, we'll rely on the caller (ChatViewModel/ToolExecutor) to provide context?
    // OR we pass a closure to fetch current session ID.
    // For now, let's assume the tool is initialized with a closure or provider.
    private let currentSessionProvider: @Sendable () async -> UUID?
    
    public init(persistenceService: PersistenceService, currentSessionProvider: @escaping @Sendable () async -> UUID?) {
        self.persistenceService = persistenceService
        self.currentSessionProvider = currentSessionProvider
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
                    "description": "UUID of the session (defaults to current session)"
                ],
                "limit": [
                    "type": "integer",
                    "description": "Max number of messages to fetch (default: 50)"
                ],
                "offset": [
                    "type": "integer",
                    "description": "Offset from the start (default: 0)"
                ]
            ]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let limit = parameters["limit"] as? Int ?? 50
        let offset = parameters["offset"] as? Int ?? 0
        
        let targetSessionId: UUID
        if let idString = parameters["session_id"] as? String, let id = UUID(uuidString: idString) {
            targetSessionId = id
        } else if let currentId = await currentSessionProvider() {
            targetSessionId = currentId
        } else {
            return .failure("No session ID provided and no active session found.")
        }
        
        do {
            let messages = try await persistenceService.fetchMessages(for: targetSessionId)
            
            // Apply pagination locally since persistence fetches all for session currently
            // (Optimization: add pagination to PersistenceService later if needed)
            let dropped = messages.dropFirst(offset)
            let page = dropped.prefix(limit)
            
            if page.isEmpty {
                return .success("No messages found in range.")
            }
            
            let formatted = page.map { msg -> String in
                let role = msg.role.uppercased()
                let time = msg.timestamp.formatted(date: .omitted, time: .shortened)
                return "[\(time)] [\(role)]: \(msg.content)"
            }.joined(separator: "\n\n")
            
            return .success("History (Total: \(messages.count), Showing: \(page.count), Offset: \(offset)):\n\n\(formatted)")
            
        } catch {
            return .failure("Failed to fetch history: \(error.localizedDescription)")
        }
    }
}

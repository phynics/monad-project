import Foundation
import OpenAI
import GRDB

/// A tool that allows the assistant to execute raw SQL queries against the local database.
public struct ExecuteSQLTool: Tool {
    public let id = "execute_sql"
    public let name = "Execute SQL"
    public let description = """
        Execute raw SQLite commands. You have wide latitude to manage your own tables and state.
        
        PROTECTED TABLES (IMMUTABLE):
        - `note`: Global instructions/facts. Deletion is BLOCKED.
        - `conversationMessage`: History of chats. Deletion/Update is BLOCKED.
        - `conversationSession`: Chat sessions. Deletion/Update is BLOCKED if archived.
        
        AVAILABLE TABLES:
        - `memory`: Used for opportunistic recall.
        - Your own custom tables: Create them as needed to manage complex state.
        
        EXAMPLES (REPLACING DEPRECATED TOOLS):
        1. List all notes: "SELECT id, name, description FROM note"
        2. Search archived chats by title: "SELECT id, title FROM conversationSession WHERE isArchived = 1 AND title LIKE '%topic%'"
        3. Load recent messages for a session (truncated): "SELECT role, SUBSTR(content, 1, 1000) as content, timestamp FROM conversationMessage WHERE sessionId = 'SESSION_UUID' ORDER BY timestamp ASC"
        4. Update a note: "UPDATE note SET content = 'New content' WHERE name = 'Persona'"
        5. Create a scratchpad table: "CREATE TABLE my_tasks (id INTEGER PRIMARY KEY, task TEXT, done BOOLEAN)"
        """
    
    public let requiresPermission = false
    
    private let persistenceService: any PersistenceServiceProtocol
    
    public init(persistenceService: any PersistenceServiceProtocol) {
        self.persistenceService = persistenceService
    }
    
    public func canExecute() async -> Bool {
        return true
    }
    
    /// Checks if the SQL command is potentially sensitive/destructive
    public func isSensitive(sql: String) -> Bool {
        let sensitiveKeywords = ["create", "drop", "delete", "update", "alter", "insert"]
        let lowerSQL = sql.lowercased()
        return sensitiveKeywords.contains { lowerSQL.contains($0) }
    }
    
    public var parametersSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "sql": [
                    "type": "string",
                    "description": "The raw SQLite command to execute."
                ]
            ],
            "required": ["sql"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let sql = parameters["sql"] as? String else {
            return .failure("Missing required parameter 'sql'")
        }
        
        do {
            let results = try await persistenceService.executeRaw(sql: sql, arguments: [])
            
            if results.isEmpty {
                return .success("Command executed successfully. No rows returned.")
            }
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(results)
            if let jsonString = String(data: data, encoding: .utf8) {
                return .success(jsonString)
            } else {
                return .failure("Failed to encode results to JSON")
            }
        } catch {
            return .failure("SQL Execution Error: \(error.localizedDescription)")
        }
    }
}

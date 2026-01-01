import Foundation
import OSLog

/// Tool to create a new memory
public final class CreateMemoryTool: Tool, @unchecked Sendable {
    public let id = "create_memory"
    public let name = "Create Memory"
    public let description = "Create a new memory entry to remember important information"
    public let requiresPermission = false

    private let persistenceManager: PersistenceManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.monad.shared", category: "CreateMemoryTool")

    public init(persistenceManager: PersistenceManager) {
        self.persistenceManager = persistenceManager
    }

    public func canExecute() async -> Bool {
        return true
    }

    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "Title of the memory",
                ],
                "content": [
                    "type": "string",
                    "description": "Content to remember",
                ],
                "tags": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Optional tags for categorization",
                ],
            ],
            "required": ["title", "content"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let title = parameters["title"] as? String,
            let content = parameters["content"] as? String
        else {
            return .failure("Missing required parameters: title and content")
        }

        let tags = parameters["tags"] as? [String] ?? []
        logger.info("Creating memory: \(title) with \(tags.count) tags")

        let memory = Memory(title: title, content: content, tags: tags)

        do {
            try await persistenceManager.saveMemory(memory)
            logger.info("Successfully created memory: \(title)")
            return .success("Memory '\(title)' created successfully.")
        } catch {
            logger.error("Failed to create memory: \(error.localizedDescription)")
            return .failure("Failed to create memory: \(error.localizedDescription)")
        }
    }
}

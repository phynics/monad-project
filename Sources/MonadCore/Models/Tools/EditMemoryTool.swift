import Foundation

/// Tool to edit an existing memory
public class EditMemoryTool: Tool, @unchecked Sendable {
    public let id = "edit_memory"
    public let name = "Edit Memory"
    public let description = "Edit an existing memory entry"
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "edit_memory", "arguments": {"memory_id": "uuid-string", "content": "Updated content"}}
        </tool_call>
        """
    }

    private let persistenceService: PersistenceService

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
    }

    public func canExecute() async -> Bool {
        return true
    }

    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "memory_id": [
                    "type": "string",
                    "description": "ID of the memory to edit",
                ],
                "title": [
                    "type": "string",
                    "description": "New title (optional)",
                ],
                "content": [
                    "type": "string",
                    "description":
                        "New content (optional). If line_index is provided, replaces line or appends.",
                ],
                "line_index": [
                    "type": "integer",
                    "description":
                        "Line number to replace (0-indexed). Use -1 to append. Default: full replace.",
                ],
            ],
            "required": ["memory_id"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let memoryIdString = parameters["memory_id"] as? String,
            let memoryId = UUID(uuidString: memoryIdString)
        else {
            return .failure("Invalid or missing parameter: memory_id")
        }

        guard let memory = try await persistenceService.fetchMemory(id: memoryId) else {
            return .failure("Memory not found with ID: \(memoryIdString)")
        }

        var updatedMemory = memory
        var changesMade = false

        // Update Title
        if let newTitle = parameters["title"] as? String {
            let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty && trimmedTitle != updatedMemory.title {
                updatedMemory.title = trimmedTitle
                changesMade = true
            }
        }

        // Update Content
        if let newContent = parameters["content"] as? String {
            do {
                if try updateContent(
                    memory: &updatedMemory, newContent: newContent, parameters: parameters)
                {
                    changesMade = true
                }
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        if changesMade {
            updatedMemory.updatedAt = Date()
            try await persistenceService.saveMemory(updatedMemory)
            return .success("Memory '\(updatedMemory.title)' updated successfully.")
        } else {
            return .success("No changes made to memory '\(updatedMemory.title)'.")
        }
    }

    private func updateContent(
        memory: inout Memory,
        newContent: String,
        parameters: [String: Any]
    ) throws -> Bool {
        if let lineIndex = parameters["line_index"] as? Int {
            // Line-based editing
            var lines = memory.content.components(separatedBy: .newlines)

            if lineIndex == -1 {
                // Append
                lines.append(newContent)
                memory.content = lines.joined(separator: "\n")
                return true
            } else if lineIndex >= 0 {
                // Replace line
                if lineIndex < lines.count {
                    lines[lineIndex] = newContent
                    memory.content = lines.joined(separator: "\n")
                    return true
                } else {
                    throw NSError(
                        domain: "EditMemoryTool", code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Line index \(lineIndex) out of bounds (count: \(lines.count))"
                        ])
                }
            } else {
                throw NSError(
                    domain: "EditMemoryTool", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Invalid line_index: \(lineIndex)"
                    ])
            }
        } else {
            // Full replacement
            if newContent != memory.content {
                memory.content = newContent
                return true
            }
        }
        return false
    }
}

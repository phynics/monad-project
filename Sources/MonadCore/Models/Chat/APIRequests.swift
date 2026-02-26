import Foundation

// MARK: - Chat Types

public struct ToolOutputSubmission: Codable, Sendable {
    public let toolCallId: String
    public let output: String

    public init(toolCallId: String, output: String) {
        self.toolCallId = toolCallId
        self.output = output
    }
}


/// A delta for a tool call in a streaming response
public struct ToolCallDelta: Sendable, Codable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let arguments: String?

    public init(index: Int, id: String? = nil, name: String? = nil, arguments: String? = nil) {
        self.index = index
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Metadata about the context used for a chat response
public struct ChatMetadata: Sendable, Codable {
    public let memories: [UUID]
    public let files: [String]

    public init(memories: [UUID] = [], files: [String] = []) {
        self.memories = memories
        self.files = files
    }
}

// MARK: - Job Types

public struct AddJobRequest: Codable, Sendable {
    public let title: String
    public let description: String?
    public let priority: Int
    public let agentId: String?
    public let parentId: UUID?

    public init(
        title: String,
        description: String? = nil,
        priority: Int = 0,
        agentId: String? = nil,
        parentId: UUID? = nil
    ) {
        self.title = title
        self.description = description
        self.priority = priority
        self.agentId = agentId
        self.parentId = parentId
    }
}
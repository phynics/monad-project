import Foundation
import GRDB

/// Individual message within a conversation
public struct ConversationMessage: Codable, Identifiable, FetchableRecord, PersistableRecord,
    Sendable
{
    public var id: UUID
    public var sessionId: UUID
    public var role: String
    public var content: String
    public var timestamp: Date
    public var recalledMemories: String
    public var memoryId: UUID?
    public var parentId: UUID?
    public var think: String?
    public var toolCalls: String
    public var toolCallId: String?

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        recalledMemories: String = "[]",
        memoryId: UUID? = nil,
        parentId: UUID? = nil,
        think: String? = nil,
        toolCalls: String = "[]",
        toolCallId: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.recalledMemories = recalledMemories
        self.memoryId = memoryId
        self.parentId = parentId
        self.think = think
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }

    public enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
        case system
        case tool
        case summary
    }

    public var messageRole: MessageRole {
        MessageRole(rawValue: role) ?? .user
    }

    /// Convert to UI Message model
    public func toMessage() -> Message {
        let memories: [Memory]
        if let data = recalledMemories.data(using: .utf8) {
            memories = (try? JSONDecoder().decode([Memory].self, from: data)) ?? []
        } else {
            memories = []
        }

        let calls: [ToolCall]
        if let data = toolCalls.data(using: .utf8) {
            calls = (try? JSONDecoder().decode([ToolCall].self, from: data)) ?? []
        } else {
            calls = []
        }

        let uiRole: Message.MessageRole =
            switch role {
            case "user": .user
            case "assistant": .assistant
            case "system": .system
            case "tool": .tool
            case "summary": .summary
            default: .user
            }

        return Message(
            id: id,
            timestamp: timestamp,
            content: content,
            role: uiRole,
            think: think,
            toolCalls: calls.isEmpty ? nil : calls,
            toolCallId: toolCallId,
            parentId: parentId,
            recalledMemories: memories.isEmpty ? nil : memories
        )
    }
}

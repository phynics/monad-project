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

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        recalledMemories: String = "[]"
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role.rawValue
        self.content = content
        self.timestamp = timestamp
        self.recalledMemories = recalledMemories
    }

    public enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
        case system
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

        return Message(
            content: content,
            role: Message.MessageRole(rawValue: role) ?? .user,
            recalledMemories: memories.isEmpty ? nil : memories
        )
    }
}

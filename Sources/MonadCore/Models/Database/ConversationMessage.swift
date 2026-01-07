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

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        role: MessageRole,
        content: String,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role.rawValue
        self.content = content
        self.timestamp = timestamp
    }

    public enum MessageRole: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public var messageRole: MessageRole {
        MessageRole(rawValue: role) ?? .user
    }
}

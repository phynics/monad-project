import Foundation
import GRDB

/// Individual message within a conversation
struct ConversationMessage: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: UUID
    var sessionId: UUID
    var role: String
    var content: String
    var timestamp: Date
    
    init(
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
    
    enum MessageRole: String, Codable {
        case user
        case assistant
        case system
    }
    
    var messageRole: MessageRole {
        MessageRole(rawValue: role) ?? .user
    }
}

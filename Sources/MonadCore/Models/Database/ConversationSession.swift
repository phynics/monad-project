import Foundation
import GRDB

/// A conversation session with messages
public struct ConversationSession: Codable, Identifiable, FetchableRecord, PersistableRecord,
    Sendable
{
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var isArchived: Bool
    public var tags: String  // JSON array stored as string

    public init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.tags = (try? JSONEncoder().encode(tags).base64EncodedString()) ?? ""
    }

    public var tagArray: [String] {
        guard let data = Data(base64Encoded: tags),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }
}

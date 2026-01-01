import Foundation
import GRDB

/// A conversation session with messages
struct ConversationSession: Codable, Identifiable, FetchableRecord, PersistableRecord {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var tags: String  // JSON array stored as string
    
    init(
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
    
    var tagArray: [String] {
        guard let data = Data(base64Encoded: tags),
              let array = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return array
    }
}

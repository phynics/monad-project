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
    public var workingDirectory: String?
    public var primaryWorkspaceId: UUID?
    public var attachedWorkspaceIds: String  // JSON array of UUIDs
    public var persona: String?  // Active persona filename

    public init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        tags: [String] = [],
        workingDirectory: String? = nil,
        primaryWorkspaceId: UUID? = nil,
        attachedWorkspaceIds: [UUID] = [],
        persona: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.workingDirectory = workingDirectory
        self.primaryWorkspaceId = primaryWorkspaceId
        self.persona = persona

        if let data = try? JSONEncoder().encode(tags), let str = String(data: data, encoding: .utf8)
        {
            self.tags = str
        } else {
            self.tags = "[]"
        }

        if let data = try? JSONEncoder().encode(attachedWorkspaceIds),
            let str = String(data: data, encoding: .utf8)
        {
            self.attachedWorkspaceIds = str
        } else {
            self.attachedWorkspaceIds = "[]"
        }
    }

    public var tagArray: [String] {
        guard let data = tags.data(using: .utf8),
            let array = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return array
    }

    public var attachedWorkspaces: [UUID] {
        guard let data = attachedWorkspaceIds.data(using: .utf8),
            let array = try? JSONDecoder().decode([UUID].self, from: data)
        else {
            return []
        }
        return array
    }
}

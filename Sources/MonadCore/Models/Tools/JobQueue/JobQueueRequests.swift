import MonadShared
import Foundation

/// Internal request to add a new job in the core framework
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

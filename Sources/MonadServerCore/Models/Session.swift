import Foundation

public struct Session: Sendable, Codable {
    public let id: UUID
    public let createdAt: Date
    public var updatedAt: Date
    
    public init(id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}

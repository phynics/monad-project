import Foundation
import GRDB

public struct MemoryEdge: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable, Equatable {
    public var id: UUID
    public var sourceId: UUID
    public var targetId: UUID
    public var relationship: String
    public var weight: Double
    public var metadata: String // JSON string
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        sourceId: UUID,
        targetId: UUID,
        relationship: String,
        weight: Double = 1.0,
        metadata: [String: String] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.relationship = relationship
        self.weight = weight
        self.createdAt = createdAt
        self.updatedAt = updatedAt

        if let data = try? JSONEncoder().encode(metadata), let str = String(data: data, encoding: .utf8) {
            self.metadata = str
        } else {
            self.metadata = "{}"
        }
    }
}

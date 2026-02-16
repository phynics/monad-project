import MonadShared
import Foundation
import GRDB

/// GRDB-compatible persistence model for CompactificationNode
public struct CompactificationNodeRecord: Codable, Identifiable, FetchableRecord, PersistableRecord,
    Sendable
{
    public static let databaseTableName = "compactificationNode"

    public var id: UUID
    public var sessionId: UUID
    public var type: String
    public var summary: String
    public var displayHint: String
    public var childIds: String  // JSON array of UUIDs
    public var metadata: String  // JSON object
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        sessionId: UUID,
        type: CompactificationType,
        summary: String,
        displayHint: String,
        childIds: [UUID],
        metadata: [String: String],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type.rawValue
        self.summary = summary
        self.displayHint = displayHint
        self.childIds = Self.encodeUUIDs(childIds)
        self.metadata = Self.encodeMetadata(metadata)
        self.createdAt = createdAt
    }

    // MARK: - Conversion

    public init(sessionId: UUID, node: CompactificationNode) {
        self.init(
            id: node.id,
            sessionId: sessionId,
            type: node.type,
            summary: node.summary,
            displayHint: node.displayHint,
            childIds: node.childIds,
            metadata: node.metadata,
            createdAt: node.createdAt
        )
    }

    public func toNode() -> CompactificationNode {
        CompactificationNode(
            id: id,
            type: CompactificationType(rawValue: type) ?? .toolExecution,
            summary: summary,
            displayHint: displayHint,
            childIds: Self.decodeUUIDs(childIds),
            metadata: Self.decodeMetadata(metadata),
            createdAt: createdAt
        )
    }

    // MARK: - Encoding Helpers

    private static func encodeUUIDs(_ uuids: [UUID]) -> String {
        let strings = uuids.map { $0.uuidString }
        guard let data = try? JSONEncoder().encode(strings),
            let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    private static func decodeUUIDs(_ json: String) -> [UUID] {
        guard let data = json.data(using: .utf8),
            let strings = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private static func encodeMetadata(_ dict: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(dict),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
    }

    private static func decodeMetadata(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
            let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return dict
    }
}

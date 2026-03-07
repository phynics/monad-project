import Foundation
import GRDB
import MonadShared

// MARK: - AgentInstance GRDB Conformance

extension AgentInstance: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String {
        "agentInstance"
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["description"] = description
        container["primaryWorkspaceId"] = primaryWorkspaceId
        container["privateTimelineId"] = privateTimelineId
        container["lastActiveAt"] = lastActiveAt
        container["createdAt"] = createdAt
        container["updatedAt"] = updatedAt

        if let metadataData = try? JSONEncoder().encode(metadata),
           let metadataString = String(data: metadataData, encoding: .utf8)
        {
            container["metadata"] = metadataString
        } else {
            container["metadata"] = "{}"
        }
    }

    public init(row: Row) throws {
        let metadataString: String? = row.hasColumn("metadata") ? row["metadata"] : nil
        let decodedMetadata: [String: AnyCodable]
        if let metaStr = metadataString, !metaStr.isEmpty,
           let data = metaStr.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data)
        {
            decodedMetadata = decoded
        } else {
            decodedMetadata = [:]
        }

        self.init(
            id: row["id"],
            name: row["name"],
            description: row["description"],
            primaryWorkspaceId: row["primaryWorkspaceId"],
            privateTimelineId: row["privateTimelineId"],
            lastActiveAt: row["lastActiveAt"],
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"],
            metadata: decodedMetadata
        )
    }
}

import Foundation
import GRDB
import MonadShared
import PKShared
import PositronicKit

// MARK: - Persistence

extension WorkspaceReference: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String {
        "workspace"
    }

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["uri"] = uri.description
        container["location"] = location.rawValue
        container["originId"] = originId

        if let toolsData = try? JSONEncoder().encode(tools),
           let toolsString = String(data: toolsData, encoding: .utf8)
        {
            container["tools"] = toolsString
        } else {
            container["tools"] = "[]"
        }

        container["rootPath"] = rootPath
        container["trustLevel"] = trustLevel.rawValue
        container["lastModifiedBy"] = lastModifiedBy
        container["status"] = status.rawValue
        container["contextInjection"] = contextInjection
        container["createdAt"] = createdAt
    }
}

// MARK: - Initializer with Row

public extension WorkspaceReference {
    init(row: Row) throws {
        let id: UUID = row["id"]

        let uriString: String = row["uri"]
        guard let uri = WorkspaceURI(parsing: uriString) else {
            throw PersistenceError.invalidUUIDFormat("Invalid WorkspaceURI: \(uriString)")
        }

        let locationColumn = row.hasColumn("location") ? "location" : "hostType"
        let locationString: String = row[locationColumn]
        let location = WorkspaceLocation(rawValue: locationString) ?? .runtime

        let originIdColumn = row.hasColumn("originId") ? "originId" : "ownerId"
        let originId: UUID? = row[originIdColumn]

        let toolsString: String? = row.hasColumn("tools") ? row["tools"] : nil
        let tools: [ToolReference]
        if let toolsStr = toolsString, !toolsStr.isEmpty {
            tools = (try? JSONDecoder().decode([ToolReference].self, from: toolsStr.data(using: .utf8) ?? Data())) ?? []
        } else {
            tools = []
        }

        let rootPath: String? = row["rootPath"]

        let trustLevelString: String = row["trustLevel"]
        let trustLevel = WorkspaceTrustLevel(rawValue: trustLevelString) ?? .full

        let lastModifiedBy: UUID? = row["lastModifiedBy"]

        let statusString: String = row["status"]
        let status = WorkspaceStatus(rawValue: statusString) ?? .active

        let contextInjection: String? = row.hasColumn("contextInjection") ? row["contextInjection"] : nil

        let createdAt: Date = row["createdAt"]

        self.init(
            id: id,
            uri: uri,
            location: location,
            originId: originId,
            tools: tools,
            rootPath: rootPath,
            trustLevel: trustLevel,
            lastModifiedBy: lastModifiedBy,
            status: status,
            contextInjection: contextInjection,
            createdAt: createdAt
        )
    }
}

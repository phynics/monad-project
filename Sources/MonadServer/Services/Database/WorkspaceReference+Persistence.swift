import Foundation
import GRDB
import MonadShared

// MARK: - Persistence

extension WorkspaceReference: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "workspace" }
    
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["uri"] = uri.description
        container["hostType"] = hostType.rawValue
        container["ownerId"] = ownerId
        
        if let toolsData = try? JSONEncoder().encode(tools),
           let toolsString = String(data: toolsData, encoding: .utf8) {
            container["tools"] = toolsString
        } else {
            container["tools"] = "[]"
        }
        
        container["rootPath"] = rootPath
        container["trustLevel"] = trustLevel.rawValue
        container["lastModifiedBy"] = lastModifiedBy
        container["status"] = status.rawValue
        container["createdAt"] = createdAt
    }
}

// MARK: - Initializer with Row

extension WorkspaceReference {
    public init(row: Row) throws {
        let id: UUID = row["id"]
        
        let uriString: String = row["uri"]
        guard let uri = WorkspaceURI(parsing: uriString) else {
            throw PersistenceError.invalidUUIDFormat("Invalid WorkspaceURI: \(uriString)")
        }
        
        let hostTypeString: String = row["hostType"]
        let hostType = WorkspaceHostType(rawValue: hostTypeString) ?? .server
        
        let ownerId: UUID? = row["ownerId"]
        
        let toolsString: String? = row.hasColumn("tools") ? row["tools"] : nil
        let tools: [ToolReference]
        if let ts = toolsString, !ts.isEmpty {
            tools = (try? JSONDecoder().decode([ToolReference].self, from: ts.data(using: .utf8) ?? Data())) ?? []
        } else {
            tools = []
        }
        
        let rootPath: String? = row["rootPath"]
        
        let trustLevelString: String = row["trustLevel"]
        let trustLevel = WorkspaceTrustLevel(rawValue: trustLevelString) ?? .full
        
        let lastModifiedBy: UUID? = row["lastModifiedBy"]
        
        let statusString: String = row["status"]
        let status = WorkspaceStatus(rawValue: statusString) ?? .active
        
        let createdAt: Date = row["createdAt"]
        
        self.init(
            id: id,
            uri: uri,
            hostType: hostType,
            ownerId: ownerId,
            tools: tools,
            rootPath: rootPath,
            trustLevel: trustLevel,
            lastModifiedBy: lastModifiedBy,
            status: status,
            createdAt: createdAt
        )
    }
}

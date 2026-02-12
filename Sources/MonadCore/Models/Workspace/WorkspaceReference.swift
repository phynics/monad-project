import Foundation
import GRDB

// MARK: - Workspace

/// A workspace reference defines the metadata and location of a workspace
public struct WorkspaceReference: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    public static var databaseTableName: String { "workspace" }
    
    public let id: UUID
    public let uri: WorkspaceURI
    public var hostType: WorkspaceHostType
    public let ownerId: UUID?  // ClientIdentity.id or nil for server-owned
    public let tools: [ToolReference]  // Tools available in this workspace
    public var rootPath: String?  // Filesystem root for the workspace
    public var trustLevel: WorkspaceTrustLevel
    public var lastModifiedBy: UUID?  // Session ID that last modified
    public var status: WorkspaceStatus
    public let createdAt: Date

    public enum WorkspaceHostType: String, Codable, Sendable, DatabaseValueConvertible {
        case server
        case serverSession  // A workspace specific to a session on the server
        case client
    }

    public enum WorkspaceStatus: String, Codable, Sendable, DatabaseValueConvertible {
        case active
        case missing
        case unknown
        
        public var databaseValue: DatabaseValue {
            items.rawValue.databaseValue
        }
        
        public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> WorkspaceStatus? {
            guard let string = String.fromDatabaseValue(dbValue) else { return nil }
            return WorkspaceStatus(rawValue: string)
        }
        // Helper to access self as items to avoid confusion if needed, or just self.rawValue
        var items: Self { self }
    }

    public init(
        id: UUID = UUID(),
        uri: WorkspaceURI,
        hostType: WorkspaceHostType,
        ownerId: UUID? = nil,
        tools: [ToolReference] = [],
        rootPath: String? = nil,
        trustLevel: WorkspaceTrustLevel = .full,
        lastModifiedBy: UUID? = nil,
        status: WorkspaceStatus = .active,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.uri = uri
        self.hostType = hostType
        self.ownerId = ownerId
        self.tools = tools
        self.rootPath = rootPath
        self.trustLevel = trustLevel
        self.lastModifiedBy = lastModifiedBy
        self.status = status
        self.createdAt = createdAt
    }

    /// Create a primary workspace for a session
    public static func primaryForSession(
        _ sessionId: UUID,
        rootPath: String
    ) -> WorkspaceReference {
        WorkspaceReference(
            uri: .serverSession(sessionId),
            hostType: .server,
            rootPath: rootPath,
            trustLevel: .full
        )
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, uri, hostType, ownerId, tools, rootPath, trustLevel, lastModifiedBy, status, createdAt
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.uri = try container.decode(WorkspaceURI.self, forKey: .uri)
        self.hostType = try container.decode(WorkspaceHostType.self, forKey: .hostType)
        self.ownerId = try container.decodeIfPresent(UUID.self, forKey: .ownerId)
        self.tools = (try? container.decode([ToolReference].self, forKey: .tools)) ?? []
        self.rootPath = try container.decodeIfPresent(String.self, forKey: .rootPath)
        self.trustLevel = try container.decode(WorkspaceTrustLevel.self, forKey: .trustLevel)
        self.lastModifiedBy = try container.decodeIfPresent(UUID.self, forKey: .lastModifiedBy)
        self.status = try container.decodeIfPresent(WorkspaceStatus.self, forKey: .status) ?? .active
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    // MARK: - EncodableRecord
    
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["uri"] = uri
        container["hostType"] = hostType
        container["ownerId"] = ownerId
        container["rootPath"] = rootPath
        container["trustLevel"] = trustLevel
        container["lastModifiedBy"] = lastModifiedBy
        container["status"] = status
        container["createdAt"] = createdAt
    }
}
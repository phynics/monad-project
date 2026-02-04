import Foundation
import GRDB

// MARK: - Workspace

/// A workspace is an execution environment where tools can operate
public struct Workspace: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    public let id: UUID
    public let uri: WorkspaceURI
    public var hostType: WorkspaceHostType
    public let ownerId: UUID?  // ClientIdentity.id or nil for server-owned
    public let tools: [ToolReference]  // Tools available in this workspace
    public let rootPath: String?  // Filesystem root for the workspace
    public var trustLevel: WorkspaceTrustLevel
    public var lastModifiedBy: UUID?  // Session ID that last modified
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        uri: WorkspaceURI,
        hostType: WorkspaceHostType,
        ownerId: UUID? = nil,
        tools: [ToolReference] = [],
        rootPath: String? = nil,
        trustLevel: WorkspaceTrustLevel = .full,
        lastModifiedBy: UUID? = nil,
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
        self.createdAt = createdAt
    }

    /// Create a primary workspace for a session
    public static func primaryForSession(
        _ sessionId: UUID,
        rootPath: String
    ) -> Workspace {
        Workspace(
            uri: .serverSession(sessionId),
            hostType: .server,
            rootPath: rootPath,
            trustLevel: .full
        )
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id, uri, hostType, ownerId, tools, rootPath, trustLevel, lastModifiedBy, createdAt
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
        container["createdAt"] = createdAt
    }
}
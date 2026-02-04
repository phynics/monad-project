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
    
    // MARK: - EncodableRecord
    
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["uri"] = uri.description
        container["hostType"] = hostType.rawValue
        container["ownerId"] = ownerId
        container["rootPath"] = rootPath
        container["trustLevel"] = trustLevel.rawValue
        container["lastModifiedBy"] = lastModifiedBy
        container["createdAt"] = createdAt
    }
}
import Foundation
import GRDB

// MARK: - Workspace URI

/// SCP-like URI for identifying workspaces
/// Format: `host:path` (e.g., `macbook:~/dev/project`, `monad-server:/sessions/abc123`)
public struct WorkspaceURI: Codable, Sendable, Hashable, CustomStringConvertible {
    public let host: String
    public let path: String

    public var description: String { "\(host):\(path)" }

    /// Whether this workspace is hosted on the server
    public var isServer: Bool { host.hasPrefix("monad-") }

    /// Whether this workspace is hosted on a client
    public var isClient: Bool { !isServer }

    public init(host: String, path: String) {
        self.host = host
        self.path = path
    }

    /// Parse a URI string like "hostname:/path/to/workspace"
    public init?(parsing uri: String) {
        guard let colonIndex = uri.firstIndex(of: ":") else { return nil }
        self.host = String(uri[..<colonIndex])
        self.path = String(uri[uri.index(after: colonIndex)...])
    }

    /// Create a server session workspace URI
    public static func serverSession(_ sessionId: UUID) -> WorkspaceURI {
        WorkspaceURI(host: "monad-server", path: "/sessions/\(sessionId.uuidString)")
    }

    /// Create a client shell workspace URI
    public static func clientShell(hostname: String) -> WorkspaceURI {
        WorkspaceURI(host: hostname, path: "~")
    }

    /// Create a client project workspace URI
    public static func clientProject(hostname: String, path: String) -> WorkspaceURI {
        WorkspaceURI(host: hostname, path: path)
    }

    /// Create a git repository workspace URI
    public static func gitRepository(url: String) -> WorkspaceURI {
        WorkspaceURI(host: "git", path: url)
    }
}

// MARK: - Workspace Host Type

public enum WorkspaceHostType: String, Codable, Sendable {
    case client
    case server
}

// MARK: - Workspace Trust Level

public enum WorkspaceTrustLevel: String, Codable, Sendable {
    case full  // Unrestricted within boundary
    case restricted  // Allowlist of operations
}

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
}

// MARK: - Workspace Lock

/// Lock held by a session during its generation cycle
public struct WorkspaceLock: Codable, Sendable {
    public let workspaceId: UUID
    public let heldBy: UUID  // Session ID
    public let acquiredAt: Date

    public init(workspaceId: UUID, heldBy: UUID, acquiredAt: Date = Date()) {
        self.workspaceId = workspaceId
        self.heldBy = heldBy
        self.acquiredAt = acquiredAt
    }
}

// MARK: - Workspace Attachment

/// Represents a workspace attached to a session
public struct WorkspaceAttachment: Codable, Sendable {
    public let workspaceId: UUID
    public let attachedAt: Date

    public init(workspaceId: UUID, attachedAt: Date = Date()) {
        self.workspaceId = workspaceId
        self.attachedAt = attachedAt
    }
}

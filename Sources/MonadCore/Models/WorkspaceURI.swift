import Foundation
import GRDB

// MARK: - Workspace URI

/// SCP-like URI for identifying workspaces
/// Format: `host:path` (e.g., `macbook:~/dev/project`, `monad-server:/sessions/abc123`)
public struct WorkspaceURI: Codable, Sendable, Hashable, CustomStringConvertible, DatabaseValueConvertible {
    public let host: String
    public let path: String

    public var description: String { "\(host):\(path)" }
    
    // MARK: - DatabaseValueConvertible
    
    public var databaseValue: DatabaseValue {
        description.databaseValue
    }
    
    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> WorkspaceURI? {
        guard let string = String.fromDatabaseValue(dbValue) else { return nil }
        return WorkspaceURI(parsing: string)
    }

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

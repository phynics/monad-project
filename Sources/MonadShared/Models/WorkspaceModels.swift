import Foundation

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

// MARK: - Workspace Trust Level

public enum WorkspaceTrustLevel: String, Codable, Sendable {
    case full  // Unrestricted within boundary
    case restricted  // Allowlist of operations
}

// MARK: - Workspace Reference

/// A workspace reference defines the metadata and location of a workspace
public struct WorkspaceReference: Codable, Sendable, Identifiable {
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

    public enum WorkspaceHostType: String, Codable, Sendable {
        case server
        case serverSession  // A workspace specific to a session on the server
        case client
    }

    public enum WorkspaceStatus: String, Codable, Sendable {
        case active
        case missing
        case unknown
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
}

// MARK: - Tool Reference

/// Reference to a tool available in a workspace
public enum ToolReference: Codable, Sendable, Hashable {
    case known(id: String)  // Server-known tool by ID
    case custom(definition: WorkspaceToolDefinition)  // Client-provided definition

    /// The tool ID regardless of type
    public var toolId: String {
        switch self {
        case .known(let id):
            return id
        case .custom(let definition):
            return definition.id
        }
    }

    /// The tool name for display
    public var displayName: String {
        switch self {
        case .known(let id):
            return id  // Server will resolve actual name
        case .custom(let definition):
            return definition.name
        }
    }

    /// Create a known tool reference
    public static func known(_ id: String) -> ToolReference {
        .known(id: id)
    }

    /// Create a custom tool reference from a definition
    public static func custom(_ definition: WorkspaceToolDefinition) -> ToolReference {
        .custom(definition: definition)
    }
}

extension ToolReference {
    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case definition
    }

    private enum ReferenceType: String, Codable {
        case known
        case custom
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ReferenceType.self, forKey: .type)

        switch type {
        case .known:
            let id = try container.decode(String.self, forKey: .id)
            self = .known(id: id)
        case .custom:
            let definition = try container.decode(WorkspaceToolDefinition.self, forKey: .definition)
            self = .custom(definition: definition)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .known(let id):
            try container.encode(ReferenceType.known, forKey: .type)
            try container.encode(id, forKey: .id)
        case .custom(let definition):
            try container.encode(ReferenceType.custom, forKey: .type)
            try container.encode(definition, forKey: .definition)
        }
    }
}

// MARK: - Workspace Tool Definition

/// Minimal definition of a tool for transfer
public struct WorkspaceToolDefinition: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let parametersSchema: [String: AnyCodable]
    public var usageExample: String?
    public var requiresPermission: Bool

    public init(
        id: String,
        name: String,
        description: String,
        parametersSchema: [String: AnyCodable] = [:],
        usageExample: String? = nil,
        requiresPermission: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.parametersSchema = parametersSchema
        self.usageExample = usageExample
        self.requiresPermission = requiresPermission
    }
}

/// A wrapper for Any that is Codable
public enum AnyCodable: Codable, Sendable, Equatable, Hashable, CustomStringConvertible {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case dictionary([String: AnyCodable])
    case array([AnyCodable])
    case null

    public var value: Any {
        switch self {
        case .string(let s): return s
        case .number(let n): return n
        case .boolean(let b): return b
        case .dictionary(let d): return d.mapValues { $0.value }
        case .array(let a): return a.map { $0.value }
        case .null: return NSNull()
        }
    }

    public var description: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return String(n)
        case .boolean(let b): return String(b)
        case .dictionary(let d): return String(describing: d)
        case .array(let a): return String(describing: a)
        case .null: return "null"
        }
    }

    public func toAny() -> Any { value }

    public var asString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var asDictionary: [String: AnyCodable]? {
        if case .dictionary(let d) = self { return d }
        return nil
    }

    public var asArray: [AnyCodable]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public init(_ value: Any?) {
        if let ac = value as? AnyCodable {
            self = ac
            return
        }
        if let value = value as? String { self = .string(value) }
        else if let value = value as? Double { self = .number(value) }
        else if let value = value as? Int { self = .number(Double(value)) }
        else if let value = value as? Bool { self = .boolean(value) }
        else if let value = value as? [String: Any] { self = .dictionary(value.mapValues { AnyCodable($0) }) }
        else if let value = value as? [Any] { self = .array(value.map { AnyCodable($0) }) }
        else { self = .null }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode([String: AnyCodable].self) { self = .dictionary(value) }
        else if let value = try? container.decode([AnyCodable].self) { self = .array(value) }
        else { self = .null }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .dictionary(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension Dictionary where Key == String, Value == AnyCodable {
    public func toJsonString() throws -> String {
        let anyDict = self.mapValues { $0.value }
        let data = try JSONSerialization.data(withJSONObject: anyDict, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

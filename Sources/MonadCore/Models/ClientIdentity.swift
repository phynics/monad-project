import Foundation
import GRDB

// MARK: - Client Identity

/// Represents a registered client that can connect to the server
public struct ClientIdentity: Codable, FetchableRecord, PersistableRecord, Sendable, Identifiable {
    public let id: UUID
    public let hostname: String
    public let displayName: String
    public let platform: String  // "macos", "linux", "ios", "web", etc.
    public let registeredAt: Date
    public var lastSeenAt: Date?

    public init(
        id: UUID = UUID(),
        hostname: String,
        displayName: String,
        platform: String,
        registeredAt: Date = Date(),
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.hostname = hostname
        self.displayName = displayName
        self.platform = platform
        self.registeredAt = registeredAt
        self.lastSeenAt = lastSeenAt
    }

    /// Default shell workspace URI for this client
    public var shellWorkspaceURI: WorkspaceURI {
        WorkspaceURI.clientShell(hostname: hostname)
    }
}

// MARK: - Client Registration Request

/// Request to register a new client with the server
public struct ClientRegistrationRequest: Codable, Sendable {
    public let hostname: String
    public let displayName: String
    public let platform: String
    public let tools: [ToolReference]

    public init(
        hostname: String,
        displayName: String,
        platform: String,
        tools: [ToolReference] = []
    ) {
        self.hostname = hostname
        self.displayName = displayName
        self.platform = platform
        self.tools = tools
    }
}

// MARK: - Client Registration Response

/// Response from client registration
public struct ClientRegistrationResponse: Codable, Sendable {
    public let client: ClientIdentity
    public let defaultWorkspace: Workspace

    public init(client: ClientIdentity, defaultWorkspace: Workspace) {
        self.client = client
        self.defaultWorkspace = defaultWorkspace
    }
}

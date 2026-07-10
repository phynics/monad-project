import Foundation
import PKShared

public struct CreateWorkspaceRequest: Codable, Sendable {
    public let uri: String
    public let location: WorkspaceReference.WorkspaceLocation
    public let originId: UUID?
    public let rootPath: String?
    public let trustLevel: WorkspaceTrustLevel?
    public let tools: [ToolReference]
    /// Optional extra text injected into the prompt context when this workspace is active.
    /// Omit (or pass `nil`) to create the workspace without a context injection.
    public let contextInjection: String?

    public init(
        uri: String,
        location: WorkspaceReference.WorkspaceLocation,
        originId: UUID?,
        rootPath: String?,
        trustLevel: WorkspaceTrustLevel?,
        tools: [ToolReference] = [],
        contextInjection: String? = nil
    ) {
        self.uri = uri
        self.location = location
        self.originId = originId
        self.rootPath = rootPath
        self.trustLevel = trustLevel
        self.tools = tools
        self.contextInjection = contextInjection
    }
}

public struct RegisterToolRequest: Codable, Sendable {
    public let tool: ToolReference

    public init(tool: ToolReference) {
        self.tool = tool
    }
}

/// Request to atomically replace all tools for a workspace.
/// Used by workspace providers to push their full tool set on connect.
public struct SyncToolsRequest: Codable, Sendable {
    public let tools: [ToolReference]

    public init(tools: [ToolReference]) {
        self.tools = tools
    }
}

public struct AttachWorkspaceRequest: Codable, Sendable {
    public let workspaceId: UUID

    public init(workspaceId: UUID) {
        self.workspaceId = workspaceId
    }
}

/// Partial-update (PATCH) request for a workspace.
///
/// Field semantics follow the codebase's PATCH convention: a `nil`/omitted field
/// means "leave unchanged". Because `contextInjection` is itself nullable on
/// `WorkspaceReference`, clearing it is expressed with the explicit
/// `clearContextInjection` flag rather than by sending `null`:
///
/// - `contextInjection == nil, clearContextInjection == false` → unchanged
/// - `contextInjection == "text"` → set to `"text"`
/// - `clearContextInjection == true` → cleared to `nil` (takes precedence
///   over any `contextInjection` value in the same request)
public struct UpdateWorkspaceRequest: Codable, Sendable {
    public let rootPath: String?
    public let trustLevel: WorkspaceTrustLevel?
    /// New context-injection text; `nil`/omitted leaves the current value unchanged.
    public let contextInjection: String?
    /// Set to `true` to clear the workspace's `contextInjection` to `nil`.
    /// Defaults to `false` (and decodes as `false` when omitted from JSON).
    public let clearContextInjection: Bool

    public init(
        rootPath: String? = nil,
        trustLevel: WorkspaceTrustLevel? = nil,
        contextInjection: String? = nil,
        clearContextInjection: Bool = false
    ) {
        self.rootPath = rootPath
        self.trustLevel = trustLevel
        self.contextInjection = contextInjection
        self.clearContextInjection = clearContextInjection
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rootPath = try container.decodeIfPresent(String.self, forKey: .rootPath)
        trustLevel = try container.decodeIfPresent(WorkspaceTrustLevel.self, forKey: .trustLevel)
        contextInjection = try container.decodeIfPresent(String.self, forKey: .contextInjection)
        clearContextInjection = try container.decodeIfPresent(Bool.self, forKey: .clearContextInjection) ?? false
    }
}

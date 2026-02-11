import Foundation

// MARK: - Workspace Tool Definition

/// A serializable tool definition for client-provided tools
public struct WorkspaceToolDefinition: Codable, Sendable, Identifiable {
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

    /// Create from an existing Tool protocol instance
    public init(from tool: any Tool) {
        self.id = tool.id
        self.name = tool.name
        self.description = tool.description
        self.requiresPermission = tool.requiresPermission
        self.usageExample = tool.usageExample

        // Convert [String: Any] to [String: AnyCodable]
        var schema: [String: AnyCodable] = [:]
        for (key, value) in tool.parametersSchema {
            schema[key] = AnyCodable(value)
        }
        self.parametersSchema = schema
    }
}
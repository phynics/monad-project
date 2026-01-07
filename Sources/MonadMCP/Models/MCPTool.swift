import Foundation
import OSLog
import Observation
import MonadCore

/// A proxy tool that forwards execution to an MCP Client
@Observable
public final class MCPTool: Tool, Identifiable, @unchecked Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let requiresPermission: Bool = true  // Default to safe permission model for now

    private let client: MCPClient
    private let toolDefinition: MCPToolDefinition

    // We store schema as [String: Any]
    private let _parametersSchema: [String: Any]

    public init(client: MCPClient, definition: MCPToolDefinition) {
        self.client = client
        self.toolDefinition = definition
        self.id = definition.name
        self.name = definition.name
        self.description = definition.description ?? "No description provided"

        // Convert AnyCodable schema to [String: Any]
        if let json = try? JSONEncoder().encode(definition.inputSchema),
            let schema = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        {
            self._parametersSchema = schema
        } else {
            self._parametersSchema = [:]
        }
    }

    public var parametersSchema: [String: Any] {
        return _parametersSchema
    }

    public func canExecute() async -> Bool {
        return true
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        do {
            // Convert to AnyCodable map
            let arguments = parameters.mapValues { AnyCodable($0) }
            let result = try await client.executeToolCall(name, arguments: arguments)

            return ToolResult.success(result)
        } catch {
            return ToolResult.failure(error.localizedDescription)
        }
    }

    private func formatContent(_ content: [MCPContent]) -> String {
        return content.compactMap { item in
            if item.type == "text" {
                return item.text
            }
            // For now ignore images or resources in simple text output
            return nil
        }.joined(separator: "\n")
    }

    // Custom Param conversion if needed, but default implementation in Tool extension might handle it
    // provided `parametersSchema` is valid JSON Schema.
}

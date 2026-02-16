import MonadShared
import Foundation

/// A protocol that defines a provider of tools for the LLM.
/// This abstraction allows different tool sources (like MCP) to be plugged in without direct dependencies.
public protocol ToolProvider: Sendable {
    /// Returns the available tools from this provider.
    func getTools() async -> [Tool]

    /// Executes a tool call from this provider.
    func executeToolCall(_ name: String, arguments: [String: AnyCodable]) async throws -> String
}

/// Helper extension to easily check if a provider has a specific tool.
extension ToolProvider {
    public func hasTool(_ name: String) async -> Bool {
        let tools = await getTools()
        return tools.contains { $0.name == name }
    }
}

import Foundation

/// Defines the capabilities and behaviors of a workspace
public protocol WorkspaceProtocol: Sendable {
    /// The unique identifier of the workspace
    var id: UUID { get }
    
    /// The metadata reference for this workspace
    var reference: WorkspaceReference { get }
    
    /// List all available tools in this workspace
    func listTools() async throws -> [ToolReference]
    
    /// Execute a specific tool in this workspace
    func executeTool(id: String, parameters: [String: AnyCodable]) async throws -> ToolResult
    
    /// Read a file from the workspace
    func readFile(path: String) async throws -> String
    
    /// Write to a file in the workspace
    func writeFile(path: String, content: String) async throws
    
    /// List files in the workspace (optionally recursively)
    func listFiles(path: String) async throws -> [String]
    
    /// Delete a file in the workspace
    func deleteFile(path: String) async throws
    
    /// Get the health/status of the workspace connection
    func healthCheck() async -> Bool
}

public enum WorkspaceError: Error, Sendable {
    case invalidWorkspaceType
    case accessDenied
    case toolExecutionNotSupported
    case workspaceNotFound
    case connectionFailed
}

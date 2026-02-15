import Foundation

/// Errors related to tool execution and routing
public enum ToolError: Error, LocalizedError, Sendable {
    case missingArgument(String)
    case invalidArgument(String)
    case executionFailed(String)
    case toolNotFound(String)
    case workspaceNotFound(UUID)
    case clientNotConnected
    case clientExecutionRequired
    
    public var errorDescription: String? {
        switch self {
        case .missingArgument(let arg):
            return "Missing required argument: \(arg)"
        case .invalidArgument(let message):
            return "Invalid argument: \(message)"
        case .executionFailed(let message):
            return "Tool execution failed: \(message)"
        case .toolNotFound(let name):
            return "Tool not found: \(name)"
        case .workspaceNotFound(let id):
            return "Workspace not found: \(id)"
        case .clientNotConnected:
            return "Client is not connected"
        case .clientExecutionRequired:
            return "Execution on client required"
        }
    }
}

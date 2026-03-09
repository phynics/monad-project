import Foundation

/// Errors related to tool execution and routing
public enum ToolError: Error, LocalizedError, Sendable {
    case missingArgument(String)
    case invalidArgument(String, expected: String, got: String)
    case executionFailed(String)
    case toolNotFound(String)
    case workspaceNotFound(UUID)
    case clientNotConnected
    case clientToolsDisallowedOnPrivateTimeline

    public var errorDescription: String? {
        switch self {
        case let .missingArgument(arg):
            return "Missing required argument: \(arg)"
        case let .invalidArgument(arg, expected, got):
            return "Invalid argument '\(arg)': expected \(expected), got \(got)"
        case let .executionFailed(message):
            return "Tool execution failed: \(message)"
        case let .toolNotFound(name):
            return "Tool not found: \(name)"
        case let .workspaceNotFound(id):
            return "Workspace not found: \(id)"
        case .clientNotConnected:
            return "Client is not connected"
        case .clientToolsDisallowedOnPrivateTimeline:
            return "Client-side tools cannot be used on private (agent-owned) timelines"
        }
    }

    /// Provides a suggested action to resolve the error.
    public var remediation: String? {
        switch self {
        case let .missingArgument(arg):
            return "Check the tool definition and ensure '\(arg)' is provided in the arguments dictionary."
        case let .invalidArgument(arg, expected, got):
            return "Convert the value for '\(arg)' to the expected type (\(expected)). Currently it is \(got)."
        case let .executionFailed(message):
            return "Review the tool logs or debug the tool implementation. Error: \(message)"
        case let .toolNotFound(name):
            return "Ensure the tool '\(name)' is registered in the TimelineToolManager."
        case let .workspaceNotFound(id):
            return "Verify that workspace \(id) exists and is currently attached."
        case .clientNotConnected:
            return "Ensure the target client is online and registered with the server."
        case .clientToolsDisallowedOnPrivateTimeline:
            return "Only server-side tools are permitted on private timelines. " +
                "Remove client workspace tools from the agent's configuration."
        }
    }
}

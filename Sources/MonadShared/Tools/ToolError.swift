import Foundation

/// Errors related to tool execution and routing
public enum ToolError: Error, LocalizedError, Sendable {
    case missingArgument(String)
    case invalidArgument(String, expected: String, got: String)
    case executionFailed(String)
    case toolNotFound(String)
    case workspaceNotFound(UUID)
    case clientNotConnected
    case clientExecutionRequired

    public var errorDescription: String? {
        switch self {
        case .missingArgument(let arg):
            return "Missing required argument: \(arg)"
        case .invalidArgument(let arg, let expected, let got):
            return "Invalid argument '\(arg)': expected \(expected), got \(got)"
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

    /// Provides a suggested action to resolve the error.
    public var remediation: String? {
        switch self {
        case .missingArgument(let arg):
            return "Check the tool definition and ensure '\(arg)' is provided in the arguments dictionary."
        case .invalidArgument(let arg, let expected, let got):
            return "Convert the value for '\(arg)' to the expected type (\(expected)). Currently it is \(got)."
        case .executionFailed(let message):
            return "Review the tool logs or debug the tool implementation. Error: \(message)"
        case .toolNotFound(let name):
            return "Ensure the tool '\(name)' is registered in the SessionToolManager."
        case .workspaceNotFound(let id):
            return "Verify that workspace \(id) exists and is currently attached."
        case .clientNotConnected:
            return "Ensure the target client is online and registered with the server."
        case .clientExecutionRequired:
            return "This tool must be executed on the client side. Ensure the CLI/Client is handling .toolExecution events."
        }
    }
}

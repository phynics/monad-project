import MonadShared
import Foundation

public enum ToolError: Error {
    case toolNotFound(String)
    case workspaceNotFound(UUID)
    case clientNotConnected
    case executionFailed(String)
    case clientExecutionRequired
}

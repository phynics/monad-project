import Foundation
import MonadCore

public struct AskAttachPWDTool: MonadCore.Tool, @unchecked Sendable {
    public let id = "ask_attach_pwd"
    public let name = "ask_attach_pwd"
    public let description = "Ask the user to attach their current working directory as a workspace. Use this when you need access to local files but no workspace is attached."
    public let requiresPermission = false
    public let parametersSchema: [String: Any] = [
        "type": "object",
        "properties": [:],
        "required": []
    ]

    public init() {}

    public func canExecute() async -> Bool {
        return true
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        return .success("[ACTION REQUIRED] Please run /workspace pwd to attach your current directory so I can access local files.")
    }
}

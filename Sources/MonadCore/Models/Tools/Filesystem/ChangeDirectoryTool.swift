import Foundation

/// Tool to change the current working directory of the session
public struct ChangeDirectoryTool: Tool, @unchecked Sendable {
    public let id = "change_directory"
    public let name = "Change Directory"
    public let description = "Change the current working directory for relative file operations."
    public let requiresPermission = false
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "change_directory", "arguments": {"path": "Sources/MonadCore"}}
        </tool_call>
        """
    }
    
    private let onChange: (String) async -> Void
    private let currentPath: String
    
    public init(currentPath: String, onChange: @escaping (String) async -> Void) {
        self.currentPath = currentPath
        self.onChange = onChange
    }
    
    public func canExecute() async -> Bool {
        return true
    }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The path to change to. Can be relative or absolute."
                ]
            ],
            "required": ["path"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let path = parameters["path"] as? String else {
            return .failure("Missing 'path' parameter")
        }
        
        // Resolve path
        let fileManager = FileManager.default
        var newPath = path
        
        if path.hasPrefix("/") {
            // Absolute path
            newPath = path
        } else if path.hasPrefix("~") {
            // Expand tilde
            newPath = (path as NSString).expandingTildeInPath
        } else {
            // Relative path
            newPath = URL(fileURLWithPath: currentPath).appendingPathComponent(path).standardized.path
        }
        
        // Validate existence and is directory
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: newPath, isDirectory: &isDir) {
            if isDir.boolValue {
                await onChange(newPath)
                return .success("Changed directory to \(newPath)")
            } else {
                return .failure("Path exists but is not a directory: \(newPath)")
            }
        } else {
            return .failure("Directory not found: \(newPath)")
        }
    }
}

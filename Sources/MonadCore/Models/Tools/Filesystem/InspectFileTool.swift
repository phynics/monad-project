import Foundation

/// Tool to inspect file metadata and type (similar to unix 'file' command)
public struct InspectFileTool: Tool, @unchecked Sendable {
    public let id = "inspect_file"
    public let name = "Inspect File"
    public let description = "Determine file type and basic metadata using the unix 'file' command."
    public let requiresPermission = false // Inspection is usually safe
    
    public var usageExample: String? {
        """
        <tool_call>
        {"name": "inspect_file", "arguments": {"path": "Sources/main.swift"}}
        </tool_call>
        """
    }
    
    public init() {}
    
    public func canExecute() async -> Bool {
        return true
    }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "path": [
                    "type": "string",
                    "description": "The path to the file to inspect"
                ]
            ],
            "required": ["path"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let pathString = parameters["path"] as? String else {
            let errorMsg = "Missing required parameter: path."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }
        
        let url = URL(fileURLWithPath: pathString).standardized
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: url.path) else {
            return .failure("File not found: \(pathString)")
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        process.arguments = [url.path]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if process.terminationStatus == 0 {
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No output"
                return .success(output)
            } else {
                let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                return .failure("File command failed with status \(process.terminationStatus): \(error)")
            }
        } catch {
            return .failure("Failed to execute file command: \(error.localizedDescription)")
        }
    }
}

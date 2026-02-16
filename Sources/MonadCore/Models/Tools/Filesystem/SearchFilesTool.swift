import MonadShared
import Foundation

/// Enhanced tool to search text content in files (search_files)
public struct SearchFilesTool: Tool, Sendable {
    public let id = "search_files"
    public let name = "Search Files"
    public let description = "Optimized search for text content across files in the workspace."
    public let requiresPermission = true

    public var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"search_files\", \"arguments\": {\"pattern\": \"TODO:\"}}
        </tool_call>
        """
    }

    private let currentDirectory: String
    private let jailRoot: String

    public init(
        currentDirectory: String = FileManager.default.currentDirectoryPath,
        jailRoot: String? = nil
    ) {
        self.currentDirectory = currentDirectory
        self.jailRoot = jailRoot ?? currentDirectory
    }

    public func canExecute() async -> Bool {
        return true
    }

    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "pattern": [
                    "type": "string",
                    "description": "The text pattern to search for (regex supported)",
                ],
                "path": [
                    "type": "string",
                    "description": "The directory to search within (default: current directory)",
                ],
                "include": [
                    "type": "string",
                    "description": "Optional glob pattern for files to include (e.g. '*.swift')",
                ]
            ],
            "required": ["pattern"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let pattern = parameters["pattern"] as? String else {
            return .failure("Missing required parameter: pattern.")
        }

        let pathString = parameters["path"] as? String ?? "."
        let includePattern = parameters["include"] as? String

        let url: URL
        do {
            url = try PathSanitizer.safelyResolve(path: pathString, within: currentDirectory, jailRoot: jailRoot)
        } catch {
            return .failure(error.localizedDescription)
        }

        // Use 'grep' for search
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/grep")
        
        var arguments = ["-rn", "--exclude-dir=.git", "--exclude-dir=.build"]
        
        if let include = includePattern {
            arguments.append("--include=\(include)")
        }
        
        arguments.append(pattern)
        arguments.append(url.path)
        
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if process.terminationStatus == 0 || process.terminationStatus == 1 {
                // status 1 means no matches found
                let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if output.isEmpty {
                    return .success("No matches found for '\(pattern)'")
                }
                
                // Limit output lines
                let lines = output.components(separatedBy: .newlines)
                if lines.count > 100 {
                    return .success(lines.prefix(100).joined(separator: "\n") + "\n... (limit reached)")
                }
                return .success(output)
            } else {
                let error = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                return .failure("Search failed with status \(process.terminationStatus): \(error)")
            }
        } catch {
            return .failure("Failed to execute search: \(error.localizedDescription)")
        }
    }
}

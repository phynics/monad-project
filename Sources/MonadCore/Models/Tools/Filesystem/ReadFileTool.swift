import MonadShared
import Foundation

/// Tool to read file content (cat)
public struct ReadFileTool: Tool, Sendable {
    public let id = "cat"
    public let name = "Read File"
    public let description = "Read the content of a file"
    public let requiresPermission = true

    public var usageExample: String? {
        """
        <tool_call>
        {"name": "cat", "arguments": {"path": "Sources/main.swift"}}
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
                "path": [
                    "type": "string",
                    "description": "The path to the file to read",
                ]
            ],
            "required": ["path"],
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

        let url: URL
        do {
            url = try PathSanitizer.safelyResolve(path: pathString, within: currentDirectory, jailRoot: jailRoot)
        } catch {
            return .failure(error.localizedDescription)
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            return .failure("File not found: \(pathString)")
        }

        do {
            // Check file size to prevent reading massive files accidentally
            let attr = try fileManager.attributesOfItem(atPath: url.path)
            let size = attr[.size] as? Int64 ?? 0

            if size > 1_000_000 {  // 1MB limit for raw cat
                return .failure(
                    "File is too large (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))). Please use document tools to load it as context."
                )
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            return .success(content)
        } catch {
            return .failure("Failed to read file: \(error.localizedDescription)")
        }
    }
}

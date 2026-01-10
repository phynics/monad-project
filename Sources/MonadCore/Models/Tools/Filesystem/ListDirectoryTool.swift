import Foundation

/// Tool to list files in a directory
public struct ListDirectoryTool: Tool, Sendable {
    public let id = "ls"
    public let name = "List Directory"
    public let description = "List files and directories at a specific path"
    public let requiresPermission = true

    public var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"ls\", \"arguments\": {\"path\": \"/Users/username/Projects\"}}
        </tool_call>
        """
    }

    private let root: String

    public init(root: String = FileManager.default.currentDirectoryPath) {
        self.root = root
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
                    "description":
                        "The path to the directory (defaults to current directory if omitted)",
                ]
            ],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        let pathString = parameters["path"] as? String ?? "."

        let url: URL
        if pathString.hasPrefix("/") {
            url = URL(fileURLWithPath: pathString).standardized
        } else if pathString.hasPrefix("~") {
            url = URL(fileURLWithPath: (pathString as NSString).expandingTildeInPath).standardized
        } else {
            url = URL(fileURLWithPath: root).appendingPathComponent(pathString).standardized
        }

        let fileManager = FileManager.default

        do {
            // Check if path exists and is a directory
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .failure("Path not found: \(pathString)")
            }

            guard isDirectory.boolValue else {
                return .failure("Path is not a directory: \(pathString)")
            }

            let contents = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )

            let formattedContents = contents.map { fileURL -> String in
                let name = fileURL.lastPathComponent
                let isDir =
                    (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

                let typeMarker = isDir ? "[DIR]" : "[FILE]"
                let sizeString =
                    isDir
                    ? "" : ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)

                return "\(typeMarker) \(name) \(sizeString)".trimmingCharacters(in: .whitespaces)
            }.sorted()

            return .success(formattedContents.joined(separator: "\n"))

        } catch {
            return .failure("Failed to list directory: \(error.localizedDescription)")
        }
    }
}

import Foundation

/// Tool to search text content in files (grep-like)
public struct SearchFileContentTool: Tool, @unchecked Sendable {
    public let id = "grep"
    public let name = "Search File Content"
    public let description = "Search for text content within files in a directory"
    public let requiresPermission = true
    
    public var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"grep\", \"arguments\": {\"path\": \"Sources\", \"pattern\": \"struct User\", \"recursive\": true}}
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
                    "description": "The directory or file to search (default: .)"
                ],
                "pattern": [
                    "type": "string",
                    "description": "The text pattern to search for"
                ],
                "recursive": [
                    "type": "boolean",
                    "description": "Whether to search recursively (default: false)"
                ]
            ],
            "required": ["pattern"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let pattern = parameters["pattern"] as? String else {
            return .failure("Missing required parameter: pattern")
        }
        
        let pathString = parameters["path"] as? String ?? "."
        let recursive = parameters["recursive"] as? Bool ?? false
        let url = URL(fileURLWithPath: pathString).standardized
        let fileManager = FileManager.default
        
        var matches: [String] = []
        
        func searchFile(at fileURL: URL) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            
            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(pattern) {
                    let relativePath = fileURL.path.replacingOccurrences(of: url.path, with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let displayPath = relativePath.isEmpty ? fileURL.lastPathComponent : relativePath
                    matches.append("\(displayPath):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
                if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: options) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        // Skip directories if not recursive (enumerator is recursive by default, so we need to check depth if we wanted to enforce strictly non-recursive, but usually grep on dir is recursive or nothing. Let's rely on enumerator but skip deeper levels if !recursive is requested manually? No, simple logic: if !recursive, we only check top level files)
                        
                        // Actually, standard grep on dir needs -r.
                        // If not recursive and it's a dir, usually it fails or does nothing.
                        // Let's assume if it is a directory, we search files inside it.
                        // If !recursive, we only look at immediate children.
                        
                        // For simplicity in this tool:
                        // If recursive, use enumerator.
                        // If not recursive, use contentsOfDirectory.
                        
                        if recursive {
                             var isDir: ObjCBool = false
                             if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                                 searchFile(at: fileURL)
                             }
                        } else {
                            // If we are iterating via enumerator, this loop IS recursive.
                            // We should probably just use separate logic.
                            break // Break loop and handle non-recursive below
                        }
                        
                        if matches.count >= 50 { break }
                    }
                }
                
                if !recursive {
                    let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                    for fileURL in contents ?? [] {
                        var isDir: ObjCBool = false
                        if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                            searchFile(at: fileURL)
                        }
                    }
                }
                
            } else {
                // It's a file
                searchFile(at: url)
            }
        } else {
            return .failure("Path not found: \(pathString)")
        }
        
        if matches.isEmpty {
            return .success("No matches found for '\(pattern)'")
        }
        
        return .success(matches.prefix(50).joined(separator: "\n") + (matches.count > 50 ? "\n... (limit reached)" : ""))
    }
}

import MonadShared
import Foundation

/// Implementation of WorkspaceProtocol for workspaces hosted on the local server filesystem
public actor LocalWorkspace: WorkspaceProtocol {
    public let reference: WorkspaceReference
    
    public nonisolated let id: UUID
    
    private let rootURL: URL
    
    public init(reference: WorkspaceReference) throws {
        guard reference.hostType == .server, let path = reference.rootPath else {
            throw WorkspaceError.invalidWorkspaceType
        }
        self.reference = reference
        self.id = reference.id
        self.rootURL = URL(fileURLWithPath: path)
    }
    
    public func listTools() async throws -> [ToolReference] {
        return reference.tools
    }
    
    public func executeTool(id: String, parameters: [String : AnyCodable]) async throws -> ToolResult {
        // Local workspaces might use the generic ToolExecutor or specialized logic.
        // For now, since tools in local workspaces are effectively system tools or scripts,
        // we might delegate this. However, LocalWorkspace usually represents a file root.
        // It might not "contain" tools in the executable sense unless they are script files.
        // If the tool is a system tool, strict execution happens elsewhere.
        // If the workspace "has" a tool, it might be a script.
        
        throw WorkspaceError.toolExecutionNotSupported
    }
    
    public func readFile(path: String) async throws -> String {
        let fileURL = rootURL.appendingPathComponent(path)
        guard fileURL.path.hasPrefix(rootURL.path) else {
             throw WorkspaceError.accessDenied
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
    
    public func writeFile(path: String, content: String) async throws {
        let fileURL = rootURL.appendingPathComponent(path)
        guard fileURL.path.hasPrefix(rootURL.path) else {
             throw WorkspaceError.accessDenied
        }
        
        // Ensure directory exists
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    public func listFiles(path: String) async throws -> [String] {
        let targetURL = rootURL.appendingPathComponent(path)
        guard targetURL.path.hasPrefix(rootURL.path) else {
             throw WorkspaceError.accessDenied
        }
        
        // Recursive listing
        var files: [String] = []
        let rootPath = rootURL.resolvingSymlinksInPath().path
        
        if let enumerator = FileManager.default.enumerator(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        {
            while let fileURL = enumerator.nextObject() as? URL {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues?.isRegularFile == true {
                    let filePath = fileURL.resolvingSymlinksInPath().path
                    if filePath.hasPrefix(rootPath) {
                        let relativePath = String(filePath.dropFirst(rootPath.count))
                            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                        files.append(relativePath)
                    }
                }
            }
        }
        return files
    }
    
    public func deleteFile(path: String) async throws {
        let fileURL = rootURL.appendingPathComponent(path)
        guard fileURL.path.hasPrefix(rootURL.path) else {
             throw WorkspaceError.accessDenied
        }
        
        try FileManager.default.removeItem(at: fileURL)
    }
    
    public func healthCheck() async -> Bool {
        return FileManager.default.fileExists(atPath: rootURL.path)
    }
}



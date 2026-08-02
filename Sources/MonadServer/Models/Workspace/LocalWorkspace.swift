import Foundation
import MonadShared
import PKShared
import PositronicKit

/// Implementation of Workspace for workspaces hosted on the local server filesystem
public actor LocalWorkspace: Workspace {
    public let reference: WorkspaceReference

    public nonisolated let id: UUID

    private let rootURL: URL

    public init(reference: WorkspaceReference) throws {
        guard reference.location == .runtime || reference.location == .runtimeTimeline,
              let path = reference.rootPath
        else {
            throw WorkspaceError.invalidWorkspaceType
        }
        self.reference = reference
        id = reference.id
        rootURL = URL(fileURLWithPath: path)
    }

    public func listTools() async throws -> [ToolReference] {
        return reference.tools
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
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func listFiles(path: String) async throws -> [String] {
        let targetURL = rootURL.appendingPathComponent(path)
        guard targetURL.path.hasPrefix(rootURL.path) else {
            throw WorkspaceError.accessDenied
        }

        // Recursive listing, scoped to the requested subdirectory (not always the workspace root).
        var files: [String] = []
        let rootPath = rootURL.resolvingSymlinksInPath().path

        if let enumerator = FileManager.default.enumerator(
            at: targetURL, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
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

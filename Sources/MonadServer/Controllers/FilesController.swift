import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct FilesController<Context: RequestContext>: Sendable {
    public let workspaceController: WorkspaceController<Context>

    public init(workspaceController: WorkspaceController<Context>) {
        self.workspaceController = workspaceController
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.get(use: listFiles)

        group.get("**", use: getFileContent)
        group.put("**", use: writeFileContent)
        group.delete("**", use: deleteFile)
    }

    // MARK: - Handlers

    @Sendable func listFiles(_ request: Request, context: Context) async throws -> Response {
        let workspaceId = try context.parameters.require("workspaceId", as: UUID.self)
        guard let workspace = try await workspaceController.getWorkspace(id: workspaceId) else {
            throw HTTPError(.notFound)
        }
        guard let rootPath = workspace.rootPath else {
            throw HTTPError(.badRequest, message: "Workspace has no root path")
        }

        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath)

        // Recursive list or just top level? Let's do recursive relative paths.
        // For security, ensure we don't go outside.
        // Enumerator approach
        var files: [String] = []
        if let enumerator = fileManager.enumerator(
            at: rootURL, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        {
            while let fileURL = enumerator.nextObject() as? URL {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if resourceValues?.isRegularFile == true {
                    let relativePath = fileURL.path.replacingOccurrences(
                        of: rootPath + "/", with: "")
                    files.append(relativePath)
                }
            }
        }

        let data = try SerializationUtils.jsonEncoder.encode(files)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func getFileContent(_ request: Request, context: Context) async throws -> Response {
        let workspaceId = try context.parameters.require("workspaceId", as: UUID.self)
        // Manually extract path from URI since we are using wildcard **
        let uriPath = request.uri.path
        guard let range = uriPath.range(of: "/files/") else {
            throw HTTPError(.badRequest, message: "Invalid path structure")
        }
        let rawPath = String(uriPath[range.upperBound...])
        guard let path = rawPath.removingPercentEncoding else {
             throw HTTPError(.badRequest, message: "Invalid path encoding")
        }
        
        // Skip hidden files or empty paths if needed, though security check handles it later.
        if path.isEmpty {
             throw HTTPError(.badRequest, message: "Empty path")
        }

        // Debug logging via Logger and Print (fallback)
        context.logger.info("[FilesController] getFileContent request: path=\(path)")

        guard let workspace = try await workspaceController.getWorkspace(id: workspaceId) else {
            context.logger.warning("[FilesController] Workspace not found: \(workspaceId)")
            print("[FilesController] Workspace not found: \(workspaceId)")
            throw HTTPError(.notFound)
        }
        guard let rootPath = workspace.rootPath else {
            context.logger.error("[FilesController] Workspace has no root path")
            print("[FilesController] Workspace has no root path")
            throw HTTPError(.badRequest, message: "Workspace has no root path")
        }

        let fileURL = URL(fileURLWithPath: rootPath).appendingPathComponent(path)
        
        context.logger.info("[FilesController] Resolving file: rootPath=\(rootPath), fullURL=\(fileURL.path)")
        print("[FilesController] Resolving file: rootPath=\(rootPath), fullURL=\(fileURL.path)")

        // Security check: Ensure fileURL is inside rootPath
        guard fileURL.standardized.path.hasPrefix(URL(fileURLWithPath: rootPath).standardized.path)
        else {
            context.logger.warning("[FilesController] Security check failed: \(fileURL.standardized.path) not in \(URL(fileURLWithPath: rootPath).standardized.path)")
            print("[FilesController] Security check failed: \(fileURL.standardized.path) not in \(URL(fileURLWithPath: rootPath).standardized.path)")
            throw HTTPError(.forbidden)
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            var headers = HTTPFields()
            headers[.contentType] = "text/plain"
            return Response(
                status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(string: content)))
        } catch {
            context.logger.error("[FilesController] Failed to read file: \(error)")
            print("[FilesController] Failed to read file: \(error)")
            throw HTTPError(.notFound)
        }
    }

    @Sendable func writeFileContent(_ request: Request, context: Context) async throws -> Response {
        let workspaceId = try context.parameters.require("workspaceId", as: UUID.self)
        guard let path = context.parameters.get("path") else {
            throw HTTPError(.badRequest, message: "Missing path")
        }

        guard let workspace = try await workspaceController.getWorkspace(id: workspaceId) else {
            throw HTTPError(.notFound)
        }
        guard let rootPath = workspace.rootPath else {
            throw HTTPError(.badRequest, message: "Workspace has no root path")
        }

        let fileURL = URL(fileURLWithPath: rootPath).appendingPathComponent(path)

        // Security check
        guard fileURL.standardized.path.hasPrefix(URL(fileURLWithPath: rootPath).standardized.path)
        else {
            throw HTTPError(.forbidden)
        }

        let buffer = try await request.body.collect(upTo: 10 * 1024 * 1024)  // 10MB limit
        let content = String(buffer: buffer)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return Response(status: .ok)
    }

    @Sendable func deleteFile(_ request: Request, context: Context) async throws -> Response {
        let workspaceId = try context.parameters.require("workspaceId", as: UUID.self)
        guard let path = context.parameters.get("path") else {
            throw HTTPError(.badRequest, message: "Missing path")
        }

        guard let workspace = try await workspaceController.getWorkspace(id: workspaceId) else {
            throw HTTPError(.notFound)
        }
        guard let rootPath = workspace.rootPath else {
            throw HTTPError(.badRequest, message: "Workspace has no root path")
        }

        let fileURL = URL(fileURLWithPath: rootPath).appendingPathComponent(path)

        // Security check
        guard fileURL.standardized.path.hasPrefix(URL(fileURLWithPath: rootPath).standardized.path)
        else {
            throw HTTPError(.forbidden)
        }

        try FileManager.default.removeItem(at: fileURL)
        return Response(status: .noContent)
    }
}

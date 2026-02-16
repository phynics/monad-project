import MonadShared
import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct FilesAPIController<Context: RequestContext>: Sendable {
    public let workspaceStore: MonadCore.WorkspaceStore

    public init(workspaceStore: MonadCore.WorkspaceStore) {
        self.workspaceStore = workspaceStore
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
        
        guard let workspace = await workspaceStore.getWorkspace(id: workspaceId) else {
             throw HTTPError(.notFound)
        }
        
        // Use an empty path to list from root, or implement recursive list in the workspace
        let files = try await workspace.listFiles(path: ".")

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
        
        guard let workspace = await workspaceStore.getWorkspace(id: workspaceId) else {
             throw HTTPError(.notFound)
        }

        do {
            let content = try await workspace.readFile(path: path)
            var headers = HTTPFields()
            headers[.contentType] = "text/plain"
            return Response(
                status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(string: content)))
        } catch {
            context.logger.error("[FilesController] Failed to read file: \(error)")
            throw HTTPError(.notFound)
        }
    }

    @Sendable func writeFileContent(_ request: Request, context: Context) async throws -> Response {
        let workspaceId = try context.parameters.require("workspaceId", as: UUID.self)
        guard let path = context.parameters.get("path") else {
            throw HTTPError(.badRequest, message: "Missing path")
        }

        guard let workspace = await workspaceStore.getWorkspace(id: workspaceId) else {
            throw HTTPError(.notFound)
        }

        let buffer = try await request.body.collect(upTo: 10 * 1024 * 1024)  // 10MB limit
        let content = String(buffer: buffer)

        try await workspace.writeFile(path: path, content: content)

        return Response(status: .ok)
    }

    @Sendable func deleteFile(_ request: Request, context: Context) async throws -> Response {
        let workspaceId = try context.parameters.require("workspaceId", as: UUID.self)
        guard let path = context.parameters.get("path") else {
            throw HTTPError(.badRequest, message: "Missing path")
        }

        guard let workspace = await workspaceStore.getWorkspace(id: workspaceId) else {
            throw HTTPError(.notFound)
        }
        
        try await workspace.deleteFile(path: path)
        return Response(status: .noContent)
    }
}

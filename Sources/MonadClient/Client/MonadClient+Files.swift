import Foundation
import MonadShared

public extension MonadWorkspaceClient {
    // MARK: - File API

    /// List all files in a workspace
    func listFiles(workspaceId: UUID) async throws -> [String] {
        let request = try await client.buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files", method: "GET"
        )
        return try await client.perform(request)
    }

    /// Get file content
    func getFileContent(workspaceId: UUID, path: String) async throws -> String {
        let request = try await client.buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "GET"
        )
        let (data, _) = try await client.performRaw(request)
        return String(decoding: data, as: UTF8.self)
    }

    /// Write file content
    func writeFileContent(workspaceId: UUID, path: String, content: String) async throws {
        var request = try await client.buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "PUT"
        )
        request.httpBody = content.data(using: .utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        _ = try await client.performRaw(request)
    }

    /// Delete a file
    func deleteFile(workspaceId: UUID, path: String) async throws {
        let request = try await client.buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "DELETE"
        )
        _ = try await client.performRaw(request)
    }
}

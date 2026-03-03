import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - File API

    /// List all files in a workspace
    public func listFiles(workspaceId: UUID) async throws -> [String] {
        let request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files", method: "GET")
        return try await perform(request)
    }

    /// Get file content
    public func getFileContent(workspaceId: UUID, path: String) async throws -> String {
        let request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "GET")
        let (data, _) = try await performRaw(request)
        return String(decoding: data, as: UTF8.self)
    }

    /// Write file content
    public func writeFileContent(workspaceId: UUID, path: String, content: String) async throws {
        var request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "PUT")
        request.httpBody = content.data(using: .utf8)
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        _ = try await performRaw(request)
    }

    /// Delete a file
    public func deleteFile(workspaceId: UUID, path: String) async throws {
        let request = try buildRequest(
            path: "/api/workspaces/\(workspaceId.uuidString)/files/\(path)", method: "DELETE")
        _ = try await performRaw(request)
    }
}

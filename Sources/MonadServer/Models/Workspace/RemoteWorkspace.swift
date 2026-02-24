import MonadCore
import MonadShared
import Foundation

/// Implementation of WorkspaceProtocol that forwards requests to a remote client via RPC/WebSocket
public actor RemoteWorkspace: WorkspaceProtocol {
    public let reference: WorkspaceReference
    public let clientId: UUID
    
    public nonisolated let id: UUID
    
    public let connectionManager: any ClientConnectionManagerProtocol
    
    public init(reference: WorkspaceReference, connectionManager: any ClientConnectionManagerProtocol) throws {
        guard reference.hostType == WorkspaceReference.WorkspaceHostType.client, let owner = reference.ownerId else {
            throw WorkspaceError.invalidWorkspaceType
        }
        self.reference = reference
        self.id = reference.id
        self.clientId = owner
        self.connectionManager = connectionManager
    }
    
    public func listTools() async throws -> [ToolReference] {
        return reference.tools
    }
    
    public func executeTool(id: String, parameters: [String : AnyCodable]) async throws -> ToolResult {
        let request = ToolExecutionRequest(toolId: id, parameters: parameters)
        
        let response = try await connectionManager.send(
            method: "workspace/executeTool",
            params: try toAnyCodable(request),
            expecting: ToolExecutionResponse.self,
            to: clientId
        )
        
        if response.isSuccess {
            return .success(response.output)
        } else {
            return .failure(response.error ?? "Unknown error")
        }
    }
    
    public func readFile(path: String) async throws -> String {
        let request = ReadFileRequest(path: path)
        let response = try await connectionManager.send(
            method: "workspace/readFile",
            params: try toAnyCodable(request),
            expecting: String.self,
            to: clientId
        )
        return response
    }
    
    public func writeFile(path: String, content: String) async throws {
        let request = WriteFileRequest(path: path, content: content)
        _ = try await connectionManager.send(
            method: "workspace/writeFile",
            params: try toAnyCodable(request),
            expecting: Bool.self,
            to: clientId
        )
    }
    
    public func deleteFile(path: String) async throws {
        let params: [String: AnyCodable] = ["path": AnyCodable(path)]
        _ = try await connectionManager.send(
            method: "workspace/deleteFile",
            params: AnyCodable(params),
            expecting: Bool.self,
            to: clientId
        )
    }
    
    public func listFiles(path: String) async throws -> [String] {
        let request = ListFilesRequest(path: path)
        let response = try await connectionManager.send(
            method: "workspace/listFiles",
            params: try toAnyCodable(request),
            expecting: [String].self,
            to: clientId
        )
        return response
    }
    
    private func toAnyCodable<T: Encodable>(_ value: T) throws -> AnyCodable {
        let data = try JSONEncoder().encode(value)
        let json = try JSONSerialization.jsonObject(with: data)
        return AnyCodable(json)
    }
    
    public func healthCheck() async -> Bool {
        return await connectionManager.isConnected(clientId: clientId)
    }
}

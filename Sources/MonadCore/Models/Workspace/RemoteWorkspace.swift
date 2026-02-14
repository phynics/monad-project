import Foundation

/// Implementation of WorkspaceProtocol that forwards requests to a remote client via RPC/WebSocket
public actor RemoteWorkspace: WorkspaceProtocol {
    public let reference: WorkspaceReference
    public let clientId: UUID
    
    public nonisolated let id: UUID
    
    // We need a way to communicate with the client.
    // In a real implementation, this would inject a connection manager or similar.
    // For this refactor, we'll define the structure and stub the communication.
    

    public let connectionManager: any ClientConnectionManagerProtocol
    
    public init(reference: WorkspaceReference, connectionManager: any ClientConnectionManagerProtocol) throws {
        guard reference.hostType == .client, let owner = reference.ownerId else {
            throw WorkspaceError.invalidWorkspaceType
        }
        self.reference = reference
        self.id = reference.id
        self.clientId = owner
        self.connectionManager = connectionManager
    }
    
    public func listTools() async throws -> [ToolReference] {
        // In a real scenario, we might query the client for dynamic tools.
        // For now, return what's in the DB reference.
        return reference.tools
    }
    
    public func executeTool(id: String, parameters: [String : AnyCodable]) async throws -> ToolResult {
        let request = ToolExecutionRequest(toolId: id, parameters: parameters)
        
        let response = try await connectionManager.send(
            method: "workspace/executeTool",
            params: AnyCodable(request),
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
            params: AnyCodable(request),
            expecting: String.self,
            to: clientId
        )
        return response
    }
    
    public func writeFile(path: String, content: String) async throws {
        let request = WriteFileRequest(path: path, content: content)
        _ = try await connectionManager.send(
            method: "workspace/writeFile",
            params: AnyCodable(request),
            expecting: Bool.self, // Expecting simple ack
            to: clientId
        )
    }
    
    public func deleteFile(path: String) async throws {
        // let request = ListFilesRequest(path: path) // Reuse struct for path? Read RPC definition.
        // We lack a dedicated DeleteFileRequest in RPC.swift, let's assume one exists or use a generic path struct.
        // Or simply define parameters inline if AnyCodable supports it.
        // Let's use AnyCodable dictionary for simplicity if strict struct is not yet defined.
        
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
            params: AnyCodable(request),
            expecting: [String].self,
            to: clientId
        )
        return response
    }
    
    public func healthCheck() async -> Bool {
        return await connectionManager.isConnected(clientId: clientId)
    }
}

import Hummingbird
import Foundation
import MonadCore
import NIOCore
import HTTPTypes

public struct ToolInfo: Codable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    
    public init(id: String, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}

public struct ExecuteToolRequest: Codable, Sendable {
    public let name: String
    public let arguments: [String: AnyCodable]
    
    public init(name: String, arguments: [String: AnyCodable]) {
        self.name = name
        self.arguments = arguments
    }
}

public struct ToolController<Context: RequestContext>: Sendable {
    public let sessionManager: SessionManager
    
    public init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }
    
    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: list)
        group.post("/execute", use: execute)
    }
    
    @Sendable func list(_ request: Request, context: Context) async throws -> [ToolInfo] {
        // For now, return an empty list or some default tools
        // In a real scenario, we might want to get tools from a global registry or per session
        return []
    }
    
    @Sendable func execute(_ request: Request, context: Context) async throws -> Response {
        let execReq = try await request.decode(as: ExecuteToolRequest.self, context: context)
        
        // Tool execution usually requires a ToolExecutor which is @MainActor
        // For the REST API MVP, we might need a non-actor ToolExecutor or a way to bridge.
        
        // For now, let's return a 404 since we don't have tools registered in the server yet.
        throw HTTPError(.notFound, message: "Tool '\(execReq.name)' not found or execution not supported via REST yet")
    }
}

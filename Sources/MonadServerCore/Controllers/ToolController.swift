import Hummingbird
import Foundation
import MonadCore
import NIOCore
import HTTPTypes

public struct ExecuteToolRequest: Codable, Sendable {
    public let sessionId: UUID
    public let name: String
    public let arguments: [String: AnyCodable]
    
    public init(sessionId: UUID, name: String, arguments: [String: AnyCodable]) {
        self.sessionId = sessionId
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
        group.get("/{id}", use: list)
        group.post("/execute", use: execute)
        group.post("/{id}/{name}/enable", use: enable)
        group.post("/{id}/{name}/disable", use: disable)
    }
    
    @Sendable func enable(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let name = try context.parameters.require("name")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        guard let toolManager = await sessionManager.getToolManager(for: id) else {
            throw HTTPError(.notFound)
        }
        
        await toolManager.enableTool(id: name) // Name implies ID in tool manager?
        return .ok
    }

    @Sendable func disable(_ request: Request, context: Context) async throws -> HTTPResponse.Status {
        let idString = try context.parameters.require("id")
        let name = try context.parameters.require("name")
        guard let id = UUID(uuidString: idString) else { throw HTTPError(.badRequest) }
        
        guard let toolManager = await sessionManager.getToolManager(for: id) else {
            throw HTTPError(.notFound)
        }
        
        await toolManager.disableTool(id: name)
        return .ok
    }
    
    @Sendable func list(_ request: Request, context: Context) async throws -> [ToolInfo] {
        let idString = try context.parameters.require("id")
        guard let id = UUID(uuidString: idString) else {
            throw HTTPError(.badRequest)
        }
        
        guard let toolManager = await sessionManager.getToolManager(for: id) else {
            throw HTTPError(.notFound)
        }
        
        let tools = await toolManager.getEnabledTools()
        return tools.map { ToolInfo(id: $0.id, name: $0.name, description: $0.description, isEnabled: true) }
    }
    
    @Sendable func execute(_ request: Request, context: Context) async throws -> Response {
        let execReq = try await request.decode(as: ExecuteToolRequest.self, context: context)
        
        guard let toolExecutor = await sessionManager.getToolExecutor(for: execReq.sessionId) else {
            throw HTTPError(.notFound)
        }
        
        let toolCall = ToolCall(name: execReq.name, arguments: execReq.arguments)
        do {
            let result = try await toolExecutor.execute(toolCall)
            return try result.response(from: request, context: context)
        } catch let error as ToolExecutorError {
            switch error {
            case .toolNotFound:
                throw HTTPError(.notFound)
            }
        } catch {
            throw error
        }
    }
}

extension Message: ResponseGenerator {
    public func response(from request: Request, context: some RequestContext) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(self)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

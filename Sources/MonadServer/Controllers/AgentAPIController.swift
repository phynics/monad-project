import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

/// Controller for discovering available agents in the framework
public struct AgentAPIController<Context: RequestContext>: Sendable {
    public let agentRegistry: AgentRegistry

    public init(agentRegistry: AgentRegistry) {
        self.agentRegistry = agentRegistry
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: list)
        group.get("/{id}", use: get)
    }

    @Sendable func list(_ request: Request, context: Context) async throws -> Response {
        let agents = await agentRegistry.listAgents()
        
        let data = try SerializationUtils.jsonEncoder.encode(agents)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func get(_ request: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id")
        
        guard let agent = await agentRegistry.getAgent(id: id) else {
            throw HTTPError(.notFound)
        }
        
        let data = try SerializationUtils.jsonEncoder.encode(agent.manifest)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

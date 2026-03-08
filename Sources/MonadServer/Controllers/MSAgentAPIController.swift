import Dependencies
import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import MonadShared
import NIOCore

/// Controller for discovering available msAgents in the framework
public struct MSAgentAPIController<Context: RequestContext>: Sendable {
    @Dependency(\.msAgentRegistry) var msAgentRegistry

    public init() {}

    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: list)
        group.get("/{id}", use: get)
    }

    @Sendable func list(_: Request, context _: Context) async throws -> Response {
        let msAgents = await msAgentRegistry.listMSAgents()

        let data = try SerializationUtils.jsonEncoder.encode(msAgents)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func get(_: Request, context: Context) async throws -> Response {
        let id = try context.parameters.require("id")

        guard let agent = await msAgentRegistry.getMSAgent(id: id) else {
            throw HTTPError(.notFound)
        }

        let data = try SerializationUtils.jsonEncoder.encode(agent)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

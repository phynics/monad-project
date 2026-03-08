import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import MonadShared
import NIOCore

/// REST controller for agent instance lifecycle management.
///
/// Routes (mounted at `/api/agents`):
/// - `GET /`                              — list all instances
/// - `POST /`                             — create a new instance
/// - `GET /:id`                           — get one instance
/// - `PATCH /:id`                         — update name/description
/// - `DELETE /:id`                        — delete (query param `?force=true`)
/// - `POST /:id/attach/:timelineId`       — attach to a timeline
/// - `DELETE /:id/attach/:timelineId`     — detach from a timeline
/// - `GET /:id/timelines`                 — list timelines attached to this agent
public struct AgentInstanceAPIController<Context: RequestContext>: Sendable {
    public let agentInstanceManager: AgentInstanceManager

    public init(agentInstanceManager: AgentInstanceManager) {
        self.agentInstanceManager = agentInstanceManager
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.get("/", use: list)
        group.post("/", use: create)
        group.get("/{id}", use: getOne)
        group.patch("/{id}", use: update)
        group.delete("/{id}", use: delete)
        group.post("/{id}/attach/{timelineId}", use: attach)
        group.delete("/{id}/attach/{timelineId}", use: detach)
        group.get("/{id}/timelines", use: listTimelines)
    }

    // MARK: - Handlers

    @Sendable func list(_: Request, context: Context) async throws -> Response {
        let instances = try await agentInstanceManager.listInstances()
        return try jsonResponse(instances, from: context)
    }

    @Sendable func create(_ request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: CreateAgentInstanceRequest.self, context: context)
        let template: MSAgent? = nil // Template lookup not supported in this endpoint
        let instance = try await agentInstanceManager.createInstance(
            from: template,
            name: input.name,
            description: input.description
        )
        return try jsonResponse(instance, status: .created, from: context)
    }

    @Sendable func getOne(_: Request, context: Context) async throws -> Response {
        let id = try requireUUID(from: context, key: "id")
        guard let instance = try await agentInstanceManager.getInstance(id: id) else {
            throw HTTPError(.notFound)
        }
        return try jsonResponse(instance, from: context)
    }

    @Sendable func update(_ request: Request, context: Context) async throws -> Response {
        let id = try requireUUID(from: context, key: "id")
        guard var instance = try await agentInstanceManager.getInstance(id: id) else {
            throw HTTPError(.notFound)
        }
        let input = try await request.decode(as: UpdateAgentInstanceRequest.self, context: context)
        if let name = input.name { instance.name = name }
        if let description = input.description { instance.description = description }
        try await agentInstanceManager.updateInstance(instance)
        return try jsonResponse(instance, from: context)
    }

    @Sendable func delete(_ request: Request, context: Context) async throws -> Response {
        let id = try requireUUID(from: context, key: "id")
        let force = request.uri.queryParameters.get("force").flatMap(Bool.init) ?? false
        do {
            try await agentInstanceManager.deleteInstance(id: id, force: force)
        } catch let error as AgentInstanceError {
            throw HTTPError(.unprocessableContent, message: error.localizedDescription)
        }
        return Response(status: .noContent)
    }

    @Sendable func attach(_: Request, context: Context) async throws -> Response {
        let agentId = try requireUUID(from: context, key: "id")
        let timelineId = try requireUUID(from: context, key: "timelineId")
        do {
            try await agentInstanceManager.attach(agentId: agentId, to: timelineId)
        } catch let error as AgentInstanceError {
            throw HTTPError(.unprocessableContent, message: error.localizedDescription)
        }
        return Response(status: .noContent)
    }

    @Sendable func detach(_: Request, context: Context) async throws -> Response {
        let agentId = try requireUUID(from: context, key: "id")
        let timelineId = try requireUUID(from: context, key: "timelineId")
        try await agentInstanceManager.detach(agentId: agentId, from: timelineId)
        return Response(status: .noContent)
    }

    @Sendable func listTimelines(_: Request, context: Context) async throws -> Response {
        let id = try requireUUID(from: context, key: "id")
        let timelines = try await agentInstanceManager.getTimelines(attachedTo: id)
        return try jsonResponse(timelines, from: context)
    }

    // MARK: - Helpers

    private func requireUUID(from context: Context, key: String) throws -> UUID {
        let str = try context.parameters.require(key)
        guard let uuid = UUID(uuidString: str) else { throw HTTPError(.badRequest) }
        return uuid
    }

    private func jsonResponse<T: Encodable>(
        _ value: T,
        status: HTTPResponse.Status = .ok,
        from _: Context
    ) throws -> Response {
        let data = try SerializationUtils.jsonEncoder.encode(value)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

// MARK: - Request Bodies

struct CreateAgentInstanceRequest: Codable {
    let name: String
    let description: String
}

struct UpdateAgentInstanceRequest: Codable {
    let name: String?
    let description: String?
}

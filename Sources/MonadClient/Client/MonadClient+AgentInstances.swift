import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - Agent Instance API

    func listAgentInstances() async throws -> [AgentInstance] {
        let request = try await client.buildRequest(path: "/api/agents", method: "GET")
        return try await client.perform(request)
    }

    func getAgentInstance(id: UUID) async throws -> AgentInstance {
        let request = try await client.buildRequest(path: "/api/agents/\(id)", method: "GET")
        return try await client.perform(request)
    }

    func createAgentInstance(name: String, description: String) async throws -> AgentInstance {
        struct Body: Encodable { let name: String; let description: String }
        var request = try await client.buildRequest(path: "/api/agents", method: "POST")
        request.httpBody = try await client.encode(Body(name: name, description: description))
        return try await client.perform(request)
    }

    func deleteAgentInstance(id: UUID, force: Bool = false) async throws {
        let path = force ? "/api/agents/\(id)?force=true" : "/api/agents/\(id)"
        let request = try await client.buildRequest(path: path, method: "DELETE")
        _ = try await client.performRaw(request)
    }

    func attachAgent(agentId: UUID, to timelineId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/agents/\(agentId)/attach/\(timelineId)", method: "POST"
        )
        _ = try await client.performRaw(request)
    }

    func detachAgent(agentId: UUID, from timelineId: UUID) async throws {
        let request = try await client.buildRequest(
            path: "/api/agents/\(agentId)/attach/\(timelineId)", method: "DELETE"
        )
        _ = try await client.performRaw(request)
    }

    func getAgentTimelines(agentId: UUID) async throws -> [TimelineResponse] {
        let request = try await client.buildRequest(path: "/api/agents/\(agentId)/timelines", method: "GET")
        return try await client.perform(request)
    }
}

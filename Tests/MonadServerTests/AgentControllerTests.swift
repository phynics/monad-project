import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
import MonadTestSupport
@testable import MonadServer
import Testing

@Suite struct AgentControllerTests {
    private func makeApp(agents: [Agent] = []) async throws -> some ApplicationProtocol {
        let mockPersistence = MockPersistenceService()
        mockPersistence.agents = agents

        return try await withDependencies {
            $0.persistenceService = mockPersistence
        } operation: {
            let registry = AgentRegistry()
            let router = Router()
            let controller = AgentAPIController<BasicRequestContext>(agentRegistry: registry)
            controller.addRoutes(to: router.group("/agents"))
            return Application(router: router)
        }
    }

    @Test("GET /agents returns empty array when no agents registered")
    func listAgents_empty() async throws {
        let app = try await makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/agents", method: .get) { response in
                #expect(response.status == .ok)
                let agents = try JSONDecoder().decode([Agent].self, from: response.body)
                #expect(agents.isEmpty)
            }
        }
    }

    @Test("GET /agents returns all registered agents")
    func listAgents_withAgents() async throws {
        let agentId = UUID()
        let agent = Agent(id: agentId, name: "Summarizer", description: "Summarizes text", systemPrompt: "You summarize.")
        let app = try await makeApp(agents: [agent])
        try await app.test(.router) { client in
            try await client.execute(uri: "/agents", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let agents = try decoder.decode([Agent].self, from: response.body)
                #expect(agents.count == 1)
                #expect(agents.first?.name == "Summarizer")
            }
        }
    }

    @Test("GET /agents/{id} returns agent found by UUID")
    func getAgent_foundByUUID() async throws {
        let agentId = UUID()
        let agent = Agent(id: agentId, name: "Writer", description: "Writes content", systemPrompt: "You write.")
        let app = try await makeApp(agents: [agent])
        try await app.test(.router) { client in
            try await client.execute(uri: "/agents/\(agentId.uuidString)", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(Agent.self, from: response.body)
                #expect(decoded.id == agentId)
                #expect(decoded.name == "Writer")
            }
        }
    }

    @Test("GET /agents/default returns the first agent")
    func getAgent_defaultKey() async throws {
        let agent = Agent(id: UUID(), name: "Default Agent", description: "Default", systemPrompt: "Default agent.")
        let app = try await makeApp(agents: [agent])
        try await app.test(.router) { client in
            try await client.execute(uri: "/agents/default", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(Agent.self, from: response.body)
                #expect(decoded.name == "Default Agent")
            }
        }
    }

    @Test("GET /agents/{id} returns 404 when agent not found")
    func getAgent_notFound() async throws {
        let app = try await makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/agents/\(UUID().uuidString)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("GET /agents returns JSON content-type")
    func listAgents_contentType() async throws {
        let app = try await makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/agents", method: .get) { response in
                #expect(response.headers[.contentType] == "application/json")
            }
        }
    }
}

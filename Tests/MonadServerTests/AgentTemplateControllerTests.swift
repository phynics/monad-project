import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import MonadTestSupport
import Testing

@Suite struct AgentTemplateControllerTests {
    private func withApp(
        agentTemplates: [AgentTemplate] = [],
        operation: @escaping @Sendable (any TestClientProtocol) async throws -> Void
    ) async throws {
        let mockPersistence = MockPersistenceService()
        mockPersistence.agentTemplates = agentTemplates

        try await withDependencies {
            $0.agentTemplateStore = mockPersistence
            $0.agentTemplateRegistry = AgentTemplateRegistry()
        } operation: {
            let router = Router()
            let controller = AgentTemplateAPIController<BasicRequestContext>()
            controller.addRoutes(to: router.group("/agentTemplates"))
            let app = Application(router: router)

            try await app.test(.router) { client in
                try await operation(client)
            }
        }
    }

    @Test("GET /agentTemplates returns empty array when no agentTemplates registered")
    func listAgentTemplates_empty() async throws {
        try await withApp { client in
            try await client.execute(uri: "/agentTemplates", method: .get) { response in
                #expect(response.status == .ok)
                let agentTemplates = try JSONDecoder().decode([AgentTemplate].self, from: response.body)
                #expect(agentTemplates.isEmpty)
            }
        }
    }

    @Test("GET /agentTemplates returns all registered agentTemplates")
    func listAgentTemplates_withAgentTemplates() async throws {
        let agentId = UUID()
        let agent = AgentTemplate(id: agentId, name: "Summarizer", description: "Summarizes text", systemPrompt: "You summarize.")
        try await withApp(agentTemplates: [agent]) { client in
            try await client.execute(uri: "/agentTemplates", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let agentTemplates = try decoder.decode([AgentTemplate].self, from: response.body)
                #expect(agentTemplates.count == 1)
                #expect(agentTemplates.first?.name == "Summarizer")
            }
        }
    }

    @Test("GET /agentTemplates/{id} returns agent found by UUID")
    func getAgentTemplate_foundByUUID() async throws {
        let agentId = UUID()
        let agent = AgentTemplate(id: agentId, name: "Writer", description: "Writes content", systemPrompt: "You write.")
        try await withApp(agentTemplates: [agent]) { client in
            try await client.execute(uri: "/agentTemplates/\(agentId.uuidString)", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(AgentTemplate.self, from: response.body)
                #expect(decoded.id == agentId)
                #expect(decoded.name == "Writer")
            }
        }
    }

    @Test("GET /agentTemplates/default returns the first agent")
    func getAgentTemplate_defaultKey() async throws {
        let agent = AgentTemplate(id: UUID(), name: "Default AgentTemplate", description: "Default", systemPrompt: "Default agent.")
        try await withApp(agentTemplates: [agent]) { client in
            try await client.execute(uri: "/agentTemplates/default", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(AgentTemplate.self, from: response.body)
                #expect(decoded.name == "Default AgentTemplate")
            }
        }
    }

    @Test("GET /agentTemplates/{id} returns 404 when agent not found")
    func getAgentTemplate_notFound() async throws {
        try await withApp { client in
            try await client.execute(uri: "/agentTemplates/\(UUID().uuidString)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("GET /agentTemplates returns JSON content-type")
    func listAgentTemplates_contentType() async throws {
        try await withApp { client in
            try await client.execute(uri: "/agentTemplates", method: .get) { response in
                #expect(response.headers[.contentType] == "application/json")
            }
        }
    }
}

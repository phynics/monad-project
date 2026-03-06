import MonadShared
import MonadCore
import Dependencies
import Foundation
import Hummingbird
import HummingbirdTesting
import MonadTestSupport
@testable import MonadServer
import Testing

@Suite struct MSAgentControllerTests {
    private func makeApp(msAgents: [MSAgent] = []) async throws -> some ApplicationProtocol {
        let mockPersistence = MockPersistenceService()
        mockPersistence.msAgents = msAgents

        return try await withDependencies {
            $0.persistenceService = mockPersistence
        } operation: {
            let registry = MSAgentRegistry()
            let router = Router()
            let controller = MSAgentAPIController<BasicRequestContext>(msAgentRegistry: registry)
            controller.addRoutes(to: router.group("/msAgents"))
            return Application(router: router)
        }
    }

    @Test("GET /msAgents returns empty array when no msAgents registered")
    func listMSAgents_empty() async throws {
        let app = try await makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/msAgents", method: .get) { response in
                #expect(response.status == .ok)
                let msAgents = try JSONDecoder().decode([MSAgent].self, from: response.body)
                #expect(msAgents.isEmpty)
            }
        }
    }

    @Test("GET /msAgents returns all registered msAgents")
    func listMSAgents_withMSAgents() async throws {
        let agentId = UUID()
        let agent = MSAgent(id: agentId, name: "Summarizer", description: "Summarizes text", systemPrompt: "You summarize.")
        let app = try await makeApp(msAgents: [agent])
        try await app.test(.router) { client in
            try await client.execute(uri: "/msAgents", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let msAgents = try decoder.decode([MSAgent].self, from: response.body)
                #expect(msAgents.count == 1)
                #expect(msAgents.first?.name == "Summarizer")
            }
        }
    }

    @Test("GET /msAgents/{id} returns agent found by UUID")
    func getMSAgent_foundByUUID() async throws {
        let agentId = UUID()
        let agent = MSAgent(id: agentId, name: "Writer", description: "Writes content", systemPrompt: "You write.")
        let app = try await makeApp(msAgents: [agent])
        try await app.test(.router) { client in
            try await client.execute(uri: "/msAgents/\(agentId.uuidString)", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(MSAgent.self, from: response.body)
                #expect(decoded.id == agentId)
                #expect(decoded.name == "Writer")
            }
        }
    }

    @Test("GET /msAgents/default returns the first agent")
    func getMSAgent_defaultKey() async throws {
        let agent = MSAgent(id: UUID(), name: "Default MSAgent", description: "Default", systemPrompt: "Default agent.")
        let app = try await makeApp(msAgents: [agent])
        try await app.test(.router) { client in
            try await client.execute(uri: "/msAgents/default", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(MSAgent.self, from: response.body)
                #expect(decoded.name == "Default MSAgent")
            }
        }
    }

    @Test("GET /msAgents/{id} returns 404 when agent not found")
    func getMSAgent_notFound() async throws {
        let app = try await makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/msAgents/\(UUID().uuidString)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("GET /msAgents returns JSON content-type")
    func listMSAgents_contentType() async throws {
        let app = try await makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/msAgents", method: .get) { response in
                #expect(response.headers[.contentType] == "application/json")
            }
        }
    }
}

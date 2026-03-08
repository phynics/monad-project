import MonadShared
import Foundation
import MonadTestSupport
import MonadCore
import Testing
import Dependencies

@Suite(.serialized)
struct AgentTemplateRegistryTests {
    private let persistence: MockPersistenceService
    private let registry: AgentTemplateRegistry

    init() async throws {
        let mock = MockPersistenceService()

        // Seed default agentTemplates
        let defaultAgentTemplate = AgentTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Default Assistant",
            description: "A helpful assistant",
            systemPrompt: "You are a helpful assistant."
        )
        let coordinatorAgentTemplate = AgentTemplate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "AgentTemplate Coordinator",
            description: "Coordinates other agentTemplates",
            systemPrompt: "You are a coordinator."
        )

        try await mock.saveAgentTemplate(defaultAgentTemplate)
        try await mock.saveAgentTemplate(coordinatorAgentTemplate)

        self.persistence = mock

        self.registry = try await withDependencies {
            $0.timelinePersistence = mock
            $0.workspacePersistence = mock
            $0.memoryStore = mock
            $0.messageStore = mock
            $0.agentTemplateStore = mock
            $0.backgroundJobStore = mock
            $0.clientStore = mock
            $0.toolPersistence = mock
            $0.agentInstanceStore = mock
        } operation: {
            AgentTemplateRegistry()
        }
    }

    @Test("Default agentTemplates are seeded")
    func testDefaultSeeds() async throws {
        let agentTemplates = await registry.listAgentTemplates()
        #expect(agentTemplates.count >= 2)

        let ids = agentTemplates.map { $0.id }
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!))

        let defaultAgentTemplate = await registry.getAgentTemplate(id: "00000000-0000-0000-0000-000000000001")
        #expect(defaultAgentTemplate?.name == "Default Assistant")
        #expect(defaultAgentTemplate?.systemPrompt.contains("assistant") == true)
    }

    @Test("Fetch agent by ID")
    func testFetchById() async throws {
        let idRaw = "00000000-0000-0000-0000-000000000002"
        let id = UUID(uuidString: idRaw)!
        let agent = await registry.getAgentTemplate(id: idRaw)
        #expect(agent != nil)
        #expect(agent?.id == id)
        #expect(agent?.name == "AgentTemplate Coordinator")
    }

    @Test("Has agent")
    func testHasAgentTemplate() async throws {
        let idRaw = "00000000-0000-0000-0000-000000000001"
        let exists = await registry.hasAgentTemplate(id: idRaw)
        #expect(exists)

        let missing = await registry.hasAgentTemplate(id: UUID().uuidString)
        #expect(!missing)
    }

    @Test("Custom agent persistence")
    func testCustomAgentTemplate() async throws {
        let customId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let customAgentTemplate = AgentTemplate(
            id: customId,
            name: "Swift Coder",
            description: "Expert in Swift programming",
            systemPrompt: "You are a senior Swift developer."
        )

        try await persistence.saveAgentTemplate(customAgentTemplate)

        let fetched = await registry.getAgentTemplate(id: customId.uuidString)
        #expect(fetched?.name == "Swift Coder")
        #expect(fetched?.systemPrompt == "You are a senior Swift developer.")
    }
}

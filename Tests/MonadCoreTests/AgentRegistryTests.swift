import MonadShared
import Foundation
import MonadCore
import Testing
import Dependencies

@Suite(.serialized)
struct AgentRegistryTests {
    private let persistence: MockPersistenceService
    private let registry: AgentRegistry

    init() async throws {
        let mock = MockPersistenceService()
        
        // Seed default agents
        let defaultAgent = Agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Default Assistant",
            description: "A helpful assistant",
            systemPrompt: "You are a helpful assistant."
        )
        let coordinatorAgent = Agent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Agent Coordinator",
            description: "Coordinates other agents",
            systemPrompt: "You are a coordinator."
        )
        
        try await mock.saveAgent(defaultAgent)
        try await mock.saveAgent(coordinatorAgent)
        
        self.persistence = mock
        
        self.registry = await withDependencies {
            $0.persistenceService = mock
        } operation: {
            AgentRegistry()
        }
    }

    @Test("Default agents are seeded")
    func testDefaultSeeds() async throws {
        let agents = await registry.listAgents()
        #expect(agents.count >= 2)
        
        let ids = agents.map { $0.id }
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!))
        
        let defaultAgent = await registry.getAgent(id: "00000000-0000-0000-0000-000000000001")
        #expect(defaultAgent?.name == "Default Assistant")
        #expect(defaultAgent?.systemPrompt.contains("assistant") == true)
    }

    @Test("Fetch agent by ID")
    func testFetchById() async throws {
        let idRaw = "00000000-0000-0000-0000-000000000002"
        let id = UUID(uuidString: idRaw)!
        let agent = await registry.getAgent(id: idRaw)
        #expect(agent != nil)
        #expect(agent?.id == id)
        #expect(agent?.name == "Agent Coordinator")
    }

    @Test("Has agent")
    func testHasAgent() async throws {
        let idRaw = "00000000-0000-0000-0000-000000000001"
        let exists = await registry.hasAgent(id: idRaw)
        #expect(exists)
        
        let missing = await registry.hasAgent(id: UUID().uuidString)
        #expect(!missing)
    }

    @Test("Custom agent persistence")
    func testCustomAgent() async throws {
        let customId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let customAgent = Agent(
            id: customId,
            name: "Swift Coder",
            description: "Expert in Swift programming",
            systemPrompt: "You are a senior Swift developer."
        )
        
        try await persistence.saveAgent(customAgent)
        
        let fetched = await registry.getAgent(id: customId.uuidString)
        #expect(fetched?.name == "Swift Coder")
        #expect(fetched?.systemPrompt == "You are a senior Swift developer.")
    }
}

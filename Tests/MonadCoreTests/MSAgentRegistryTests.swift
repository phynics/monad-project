import MonadShared
import Foundation
import MonadTestSupport
import MonadCore
import Testing
import Dependencies

@Suite(.serialized)
struct MSAgentRegistryTests {
    private let persistence: MockPersistenceService
    private let registry: MSAgentRegistry

    init() async throws {
        let mock = MockPersistenceService()

        // Seed default msAgents
        let defaultMSAgent = MSAgent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Default Assistant",
            description: "A helpful assistant",
            systemPrompt: "You are a helpful assistant."
        )
        let coordinatorMSAgent = MSAgent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "MSAgent Coordinator",
            description: "Coordinates other msAgents",
            systemPrompt: "You are a coordinator."
        )

        try await mock.saveMSAgent(defaultMSAgent)
        try await mock.saveMSAgent(coordinatorMSAgent)

        self.persistence = mock

        self.registry = try await withDependencies {
            $0.persistenceService = mock
        } operation: {
            MSAgentRegistry()
        }
    }

    @Test("Default msAgents are seeded")
    func testDefaultSeeds() async throws {
        let msAgents = await registry.listMSAgents()
        #expect(msAgents.count >= 2)

        let ids = msAgents.map { $0.id }
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
        #expect(ids.contains(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!))

        let defaultMSAgent = await registry.getMSAgent(id: "00000000-0000-0000-0000-000000000001")
        #expect(defaultMSAgent?.name == "Default Assistant")
        #expect(defaultMSAgent?.systemPrompt.contains("assistant") == true)
    }

    @Test("Fetch agent by ID")
    func testFetchById() async throws {
        let idRaw = "00000000-0000-0000-0000-000000000002"
        let id = UUID(uuidString: idRaw)!
        let agent = await registry.getMSAgent(id: idRaw)
        #expect(agent != nil)
        #expect(agent?.id == id)
        #expect(agent?.name == "MSAgent Coordinator")
    }

    @Test("Has agent")
    func testHasMSAgent() async throws {
        let idRaw = "00000000-0000-0000-0000-000000000001"
        let exists = await registry.hasMSAgent(id: idRaw)
        #expect(exists)

        let missing = await registry.hasMSAgent(id: UUID().uuidString)
        #expect(!missing)
    }

    @Test("Custom agent persistence")
    func testCustomMSAgent() async throws {
        let customId = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let customMSAgent = MSAgent(
            id: customId,
            name: "Swift Coder",
            description: "Expert in Swift programming",
            systemPrompt: "You are a senior Swift developer."
        )

        try await persistence.saveMSAgent(customMSAgent)

        let fetched = await registry.getMSAgent(id: customId.uuidString)
        #expect(fetched?.name == "Swift Coder")
        #expect(fetched?.systemPrompt == "You are a senior Swift developer.")
    }
}

import MonadShared
import Foundation
import GRDB
import MonadCore
import Testing
import Dependencies

@Suite(.serialized)
struct AgentRegistryTests {
    private let persistence: PersistenceService
    private let registry: AgentRegistry

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        let persistenceService = PersistenceService(dbQueue: queue)
        self.persistence = persistenceService
        
        self.registry = await withDependencies {
            $0.persistenceService = persistenceService
        } operation: {
            AgentRegistry()
        }
    }

    @Test("Default agents are seeded")
    func testDefaultSeeds() async throws {
        let agents = await registry.listAgents()
        #expect(agents.count >= 2)
        
        let ids = agents.map { $0.id }
        #expect(ids.contains("default"))
        #expect(ids.contains("coordinator"))
        
        let defaultAgent = await registry.getAgent(id: "default")
        #expect(defaultAgent?.name == "Default Assistant")
        #expect(defaultAgent?.systemPrompt.contains("Monad") == true)
    }

    @Test("Fetch agent by ID")
    func testFetchById() async throws {
        let agent = await registry.getAgent(id: "coordinator")
        #expect(agent != nil)
        #expect(agent?.id == "coordinator")
        #expect(agent?.name == "Agent Coordinator")
    }

    @Test("Has agent")
    func testHasAgent() async throws {
        let exists = await registry.hasAgent(id: "default")
        #expect(exists)
        
        let missing = await registry.hasAgent(id: "non-existent")
        #expect(!missing)
    }

    @Test("Custom agent persistence")
    func testCustomAgent() async throws {
        let customAgent = Agent(
            id: "coder",
            name: "Swift Coder",
            description: "Expert in Swift programming",
            systemPrompt: "You are a senior Swift developer."
        )
        
        try await persistence.databaseWriter.write { db in
            try customAgent.insert(db)
        }
        
        let fetched = await registry.getAgent(id: "coder")
        #expect(fetched?.name == "Swift Coder")
        #expect(fetched?.systemPrompt == "You are a senior Swift developer.")
    }
}

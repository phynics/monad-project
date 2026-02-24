import Testing
import Foundation
import MonadShared
@testable import MonadCore

@Suite("Persistence Protocol Tests")
struct PersistenceProtocolTests {

    // This test verifies that we can define a mock that conforms to all new domain protocols
    // effectively replacing the God protocol with composed requirements.
    @Test("Protocol Composition Test")
    func testProtocolComposition() async throws {
        let mock = MockPersistenceStore()

        // Verify it conforms to all required domains
        #expect(mock is MemoryStoreProtocol)
        #expect(mock is MessageStoreProtocol)
        #expect(mock is SessionPersistenceProtocol)
        #expect(mock is JobStoreProtocol)
        #expect(mock is AgentStoreProtocol)
        #expect(mock is WorkspacePersistenceProtocol)
        #expect(mock is ClientStoreProtocol)
        #expect(mock is ToolPersistenceProtocol)
    }
}

// Minimal mock to verify protocol definitions exist
final class MockPersistenceStore:
    MemoryStoreProtocol,
    MessageStoreProtocol,
    SessionPersistenceProtocol,
    JobStoreProtocol,
    AgentStoreProtocol,
    WorkspacePersistenceProtocol,
    ClientStoreProtocol,
    ToolPersistenceProtocol,
    @unchecked Sendable {
    // MemoryStoreProtocol
    func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID { UUID() }
    func fetchMemory(id: UUID) async throws -> Memory? { nil }
    func fetchAllMemories() async throws -> [Memory] { [] }
    func searchMemories(query: String) async throws -> [Memory] { [] }
    func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)] { [] }
    func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] { [] }
    func deleteMemory(id: UUID) async throws {}
    func updateMemory(_ memory: Memory) async throws {}
    func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws {}
    func vacuumMemories(threshold: Double) async throws -> Int { 0 }

    // MessageStoreProtocol
    func saveMessage(_ message: ConversationMessage) async throws {}
    func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] { [] }
    func deleteMessages(for sessionId: UUID) async throws {}

    // SessionPersistenceProtocol
    func saveSession(_ session: ConversationSession) async throws {}
    func fetchSession(id: UUID) async throws -> ConversationSession? { nil }
    func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession] { [] }
    func deleteSession(id: UUID) async throws {}

    // JobStoreProtocol
    func saveJob(_ job: Job) async throws {}
    func fetchJob(id: UUID) async throws -> Job? { nil }
    func fetchAllJobs() async throws -> [Job] { [] }
    func fetchJobs(for sessionId: UUID) async throws -> [Job] { [] }
    func fetchPendingJobs(limit: Int) async throws -> [Job] { [] }
    func deleteJob(id: UUID) async throws {}
    func monitorJobs() async -> AsyncStream<JobEvent> { .init { _ in } }

    // AgentStoreProtocol
    func saveAgent(_ agent: Agent) async throws {}
    func fetchAgent(id: UUID) async throws -> Agent? { nil }
    func fetchAgent(key: String) async throws -> Agent? { nil }
    func fetchAllAgents() async throws -> [Agent] { [] }
    func hasAgent(id: String) async -> Bool { false }

    // WorkspacePersistenceProtocol
    func saveWorkspace(_ workspace: WorkspaceReference) async throws {}
    func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? { nil }
    func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? { nil }
    func fetchAllWorkspaces() async throws -> [WorkspaceReference] { [] }
    func deleteWorkspace(id: UUID) async throws {}

    // ClientStoreProtocol
    func saveClient(_ client: ClientIdentity) async throws {}
    func fetchClient(id: UUID) async throws -> ClientIdentity? { nil }
    func fetchAllClients() async throws -> [ClientIdentity] { [] }
    func deleteClient(id: UUID) async throws -> Bool { false }

    // ToolPersistenceProtocol
    func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws {}
    func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] { [] }
    func fetchClientTools(clientId: UUID) async throws -> [ToolReference] { [] }
    func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? { nil }
    func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String? { nil }
}

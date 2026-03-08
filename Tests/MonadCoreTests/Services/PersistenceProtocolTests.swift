import Testing
import Foundation
@testable import MonadCore
@testable import MonadShared

@Suite("Persistence Protocol Tests")
struct PersistenceProtocolTests {

    // This test verifies that we can define a mock that conforms to all new domain protocols
    // effectively replacing the God protocol with composed requirements.
    @Test("Protocol Composition Test")
    func testProtocolComposition() async throws {
        let mock = MockPersistenceStore()

        // Verify it conforms to all required domains
        let _: MemoryStoreProtocol = mock
        let _: MessageStoreProtocol = mock
        let _: TimelinePersistenceProtocol = mock
        let _: BackgroundJobStoreProtocol = mock
        let _: MSAgentStoreProtocol = mock
        let _: WorkspacePersistenceProtocol = mock
        let _: ToolPersistenceProtocol = mock
    }
}

// Minimal mock to verify protocol definitions exist
final class MockPersistenceStore:
    MemoryStoreProtocol,
    MessageStoreProtocol,
    TimelinePersistenceProtocol,
    BackgroundJobStoreProtocol,
    MSAgentStoreProtocol,
    WorkspacePersistenceProtocol,
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
    func pruneMemories(matching query: String, dryRun: Bool) async throws -> Int { 0 }
    func pruneMemories(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws -> Int { 0 }

    // MessageStoreProtocol
    func saveMessage(_ message: ConversationMessage) async throws {}
    func fetchMessages(for timelineId: UUID) async throws -> [ConversationMessage] { [] }
    func deleteMessages(for timelineId: UUID) async throws {}
    func pruneMessages(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws -> Int { 0 }

    // TimelinePersistenceProtocol
    func saveTimeline(_ session: Timeline) async throws {}
    func fetchTimeline(id: UUID) async throws -> Timeline? { nil }
    func fetchAllTimelines(includeArchived: Bool) async throws -> [Timeline] { [] }
    func deleteTimeline(id: UUID) async throws {}
    func pruneTimelines(olderThan timeInterval: TimeInterval, excluding excludedTimelineIds: [UUID], dryRun: Bool) async throws -> Int { 0 }

    // BackgroundJobStoreProtocol
    func saveJob(_ job: BackgroundJob) async throws {}
    func fetchJob(id: UUID) async throws -> BackgroundJob? { nil }
    func fetchAllJobs() async throws -> [BackgroundJob] { [] }
    func fetchJobs(for timelineId: UUID) async throws -> [BackgroundJob] { [] }
    func fetchPendingJobs(limit: Int) async throws -> [BackgroundJob] { [] }
    func deleteJob(id: UUID) async throws {}
    func monitorJobs() async -> AsyncStream<BackgroundJobEvent> { .init { _ in } }

    // MSAgentStoreProtocol
    func saveMSAgent(_ agent: MSAgent) async throws {}
    func fetchMSAgent(id: UUID) async throws -> MSAgent? { nil }
    func fetchMSAgent(key: String) async throws -> MSAgent? { nil }
    func fetchAllMSAgents() async throws -> [MSAgent] { [] }
    func hasMSAgent(id: String) async -> Bool { false }

    // WorkspacePersistenceProtocol
    func saveWorkspace(_ workspace: WorkspaceReference) async throws {}
    func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? { nil }
    func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? { nil }
    func fetchAllWorkspaces() async throws -> [WorkspaceReference] { [] }
    func deleteWorkspace(id: UUID) async throws {}


    // ToolPersistenceProtocol
    func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws {}
    func syncTools(workspaceId: UUID, tools: [ToolReference]) async throws {}
    func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] { [] }
    func fetchClientTools(clientId: UUID) async throws -> [ToolReference] { [] }
    func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? { nil }
    func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String? { nil }
}

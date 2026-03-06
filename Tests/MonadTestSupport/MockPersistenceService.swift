@testable import MonadCore
import Foundation

public final class MockPersistenceService: FullPersistenceService, @unchecked Sendable {
    private let memoriesMock = MockMemoryStore()
    private let messagesMock = MockMessageStore()
    private let sessionsMock = MockSessionPersistence()
    private let jobsMock = MockJobStore()
    private let msAgentsMock = MockMSAgentStore()
    private let workspacesMock = MockWorkspacePersistence()
    private let toolsMock = MockToolPersistence()

    public var mockHealthStatus: HealthStatus = .ok
    public var mockHealthDetails: [String: String]? = ["mock": "true"]

    // Mocks
    public var saveClientMock: ((ClientIdentity) async throws -> Void)?
    public var fetchClientMock: ((UUID) async throws -> ClientIdentity?)?
    public var fetchAllClientsMock: (() async throws -> [ClientIdentity])?
    public var deleteClientMock: ((UUID) async throws -> Bool)?
    
    public init() {}

    public func getHealthStatus() async -> HealthStatus { mockHealthStatus }
    public func getHealthDetails() async -> [String: String]? { mockHealthDetails }
    public func checkHealth() async -> HealthStatus { mockHealthStatus }

    // MARK: - MemoryStoreProtocol
    public var memories: [Memory] {
        get { memoriesMock.memories }
        set { memoriesMock.memories = newValue }
    }
    public var searchResults: [(memory: Memory, similarity: Double)] {
        get { memoriesMock.searchResults }
        set { memoriesMock.searchResults = newValue }
    }
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID { try await memoriesMock.saveMemory(memory, policy: policy) }
    public func fetchMemory(id: UUID) async throws -> Memory? { try await memoriesMock.fetchMemory(id: id) }
    public func fetchAllMemories() async throws -> [Memory] { try await memoriesMock.fetchAllMemories() }
    public func searchMemories(query: String) async throws -> [Memory] { try await memoriesMock.searchMemories(query: query) }
    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)] { try await memoriesMock.searchMemories(embedding: embedding, limit: limit, minSimilarity: minSimilarity) }
    public func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] { try await memoriesMock.searchMemories(matchingAnyTag: tags) }
    public func deleteMemory(id: UUID) async throws { try await memoriesMock.deleteMemory(id: id) }
    public func updateMemory(_ memory: Memory) async throws { try await memoriesMock.updateMemory(memory) }
    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws { try await memoriesMock.updateMemoryEmbedding(id: id, newEmbedding: newEmbedding) }
    public func vacuumMemories(threshold: Double) async throws -> Int { try await memoriesMock.vacuumMemories(threshold: threshold) }

    // MARK: - MessageStoreProtocol
    public var messages: [ConversationMessage] {
        get { messagesMock.messages }
        set { messagesMock.messages = newValue }
    }
    public func saveMessage(_ message: ConversationMessage) async throws { try await messagesMock.saveMessage(message) }
    public func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] { try await messagesMock.fetchMessages(for: sessionId) }
    public func deleteMessages(for sessionId: UUID) async throws { try await messagesMock.deleteMessages(for: sessionId) }

    // MARK: - SessionPersistenceProtocol
    public var sessions: [Timeline] {
        get { sessionsMock.sessions }
        set { sessionsMock.sessions = newValue }
    }
    public func saveSession(_ session: Timeline) async throws { try await sessionsMock.saveSession(session) }
    public func fetchSession(id: UUID) async throws -> Timeline? { try await sessionsMock.fetchSession(id: id) }
    public func fetchAllSessions(includeArchived: Bool) async throws -> [Timeline] { try await sessionsMock.fetchAllSessions(includeArchived: includeArchived) }
    public func deleteSession(id: UUID) async throws { try await sessionsMock.deleteSession(id: id) }

    // MARK: - JobStoreProtocol
    public var jobs: [Job] {
        get { jobsMock.jobs }
        set { jobsMock.jobs = newValue }
    }
    public func saveJob(_ job: Job) async throws { try await jobsMock.saveJob(job) }
    public func fetchJob(id: UUID) async throws -> Job? { try await jobsMock.fetchJob(id: id) }
    public func fetchAllJobs() async throws -> [Job] { try await jobsMock.fetchAllJobs() }
    public func fetchJobs(for sessionId: UUID) async throws -> [Job] { try await jobsMock.fetchJobs(for: sessionId) }
    public func fetchPendingJobs(limit: Int) async throws -> [Job] { try await jobsMock.fetchPendingJobs(limit: limit) }
    public func deleteJob(id: UUID) async throws { try await jobsMock.deleteJob(id: id) }
    public func monitorJobs() async -> AsyncStream<JobEvent> { await jobsMock.monitorJobs() }

    // MARK: - MSAgentStoreProtocol
    public var msAgents: [MSAgent] {
        get { msAgentsMock.msAgents }
        set { msAgentsMock.msAgents = newValue }
    }
    public func saveMSAgent(_ agent: MSAgent) async throws { try await msAgentsMock.saveMSAgent(agent) }
    public func fetchMSAgent(id: UUID) async throws -> MSAgent? { try await msAgentsMock.fetchMSAgent(id: id) }
    public func fetchMSAgent(key: String) async throws -> MSAgent? { try await msAgentsMock.fetchMSAgent(key: key) }
    public func fetchAllMSAgents() async throws -> [MSAgent] { try await msAgentsMock.fetchAllMSAgents() }
    public func hasMSAgent(id: String) async -> Bool { await msAgentsMock.hasMSAgent(id: id) }

    // MARK: - WorkspacePersistenceProtocol
    public var workspaces: [WorkspaceReference] {
        get { workspacesMock.workspaces }
        set { workspacesMock.workspaces = newValue }
    }
    public func saveWorkspace(_ workspace: WorkspaceReference) async throws {
        try await workspacesMock.saveWorkspace(workspace)
        if let idx = toolsMock.workspaces.firstIndex(where: { $0.id == workspace.id }) {
            toolsMock.workspaces[idx] = workspace
        } else {
            toolsMock.workspaces.append(workspace)
        }
    }
    public func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? { try await workspacesMock.fetchWorkspace(id: id) }
    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? { try await workspacesMock.fetchWorkspace(id: id, includeTools: includeTools) }
    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] { try await workspacesMock.fetchAllWorkspaces() }
    public func deleteWorkspace(id: UUID) async throws { try await workspacesMock.deleteWorkspace(id: id) }

    // MARK: - ToolPersistenceProtocol
    public func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws {
        try await toolsMock.addToolToWorkspace(workspaceId: workspaceId, tool: tool)
    }
    public func syncTools(workspaceId: UUID, tools: [ToolReference]) async throws {
        try await toolsMock.syncTools(workspaceId: workspaceId, tools: tools)
    }
    public func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] {
        try await toolsMock.fetchTools(forWorkspaces: workspaceIds)
    }
    public func fetchClientTools(clientId: UUID) async throws -> [ToolReference] {
        try await toolsMock.fetchClientTools(clientId: clientId)
    }
    public func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? {
        try await toolsMock.findWorkspaceId(forToolId: toolId, in: workspaceIds)
    }
    public func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String? {
        try await toolsMock.fetchToolSource(toolId: toolId, workspaceIds: workspaceIds, primaryWorkspaceId: primaryWorkspaceId)
    }

    // MARK: - ClientStoreProtocol

    public func saveClient(_ client: ClientIdentity) async throws {
        if let mock = saveClientMock { try await mock(client) }
    }

    public func fetchClient(id: UUID) async throws -> ClientIdentity? {
        if let mock = fetchClientMock { return try await mock(id) }
        return nil
    }

    public func fetchAllClients() async throws -> [ClientIdentity] {
        if let mock = fetchAllClientsMock { return try await mock() }
        return []
    }

    public func deleteClient(id: UUID) async throws -> Bool {
        if let mock = deleteClientMock { return try await mock(id) }
        return false
    }

    public func resetDatabase() async throws {
        memories = []
        searchResults = []
        messages = []
        sessions = []
        jobs = []
        msAgents = []
        workspaces = []
    }
}

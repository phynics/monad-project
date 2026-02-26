import Foundation

public final class MockPersistenceService: FullPersistenceService, @unchecked Sendable {
    private let memoriesMock = MockMemoryStore()
    private let messagesMock = MockMessageStore()
    private let sessionsMock = MockSessionPersistence()
    private let jobsMock = MockJobStore()
    private let agentsMock = MockAgentStore()
    private let workspacesMock = MockWorkspacePersistence()
    private let toolsMock = MockToolPersistence()

    public var mockHealthStatus: HealthStatus = .ok
    public var mockHealthDetails: [String: String]? = ["mock": "true"]

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

    // MARK: - AgentStoreProtocol
    public var agents: [Agent] {
        get { agentsMock.agents }
        set { agentsMock.agents = newValue }
    }
    public func saveAgent(_ agent: Agent) async throws { try await agentsMock.saveAgent(agent) }
    public func fetchAgent(id: UUID) async throws -> Agent? { try await agentsMock.fetchAgent(id: id) }
    public func fetchAgent(key: String) async throws -> Agent? { try await agentsMock.fetchAgent(key: key) }
    public func fetchAllAgents() async throws -> [Agent] { try await agentsMock.fetchAllAgents() }
    public func hasAgent(id: String) async -> Bool { await agentsMock.hasAgent(id: id) }

    // MARK: - WorkspacePersistenceProtocol
    public var workspaces: [WorkspaceReference] {
        get { workspacesMock.workspaces }
        set { workspacesMock.workspaces = newValue }
    }
    public func saveWorkspace(_ workspace: WorkspaceReference) async throws { try await workspacesMock.saveWorkspace(workspace) }
    public func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? { try await workspacesMock.fetchWorkspace(id: id) }
    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? { try await workspacesMock.fetchWorkspace(id: id, includeTools: includeTools) }
    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] { try await workspacesMock.fetchAllWorkspaces() }
    public func deleteWorkspace(id: UUID) async throws { try await workspacesMock.deleteWorkspace(id: id) }


    // MARK: - ToolPersistenceProtocol
    public func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws { 
        try await toolsMock.addToolToWorkspace(workspaceId: workspaceId, tool: tool) 
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

    public func resetDatabase() async throws {
        memories = []
        searchResults = []
        messages = []
        sessions = []
        jobs = []
        agents = []
        workspaces = []
    }
}
import Dependencies
import Foundation

// MARK: - Dependency Keys

public typealias FullPersistenceService = 
    MemoryStoreProtocol & 
    MessageStoreProtocol & 
    SessionPersistenceProtocol & 
    JobStoreProtocol & 
    AgentStoreProtocol & 
    WorkspacePersistenceProtocol & 
    ToolPersistenceProtocol & 
    HealthCheckable

public enum PersistenceServiceKey: DependencyKey {
    public static let liveValue: any FullPersistenceService = UnconfiguredPersistenceService()
    public static let testValue: any FullPersistenceService = UnconfiguredPersistenceService()
}

public enum VectorStoreKey: DependencyKey {
    public static let liveValue: (any VectorStoreProtocol)? = nil
}

// MARK: - Dependency Values

extension DependencyValues {
    public var persistenceService: any FullPersistenceService {
        get { self[PersistenceServiceKey.self] }
        set { self[PersistenceServiceKey.self] = newValue }
    }

    public var vectorStore: (any VectorStoreProtocol)? {
        get { self[VectorStoreKey.self] }
        set { self[VectorStoreKey.self] = newValue }
    }
}

// MARK: - Placeholder Implementations

public struct UnconfiguredPersistenceService: FullPersistenceService {
    public init() {}
    
    private func fail() -> Never {
        fatalError("PersistenceService not configured. Call 'MonadCore.configure()'.")
    }

    public func getHealthStatus() async -> HealthStatus { .down }
    public func getHealthDetails() async -> [String : String]? { ["error": "Unconfigured"] }
    public func checkHealth() async -> HealthStatus { .down }
    
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID { fail() }
    public func fetchMemory(id: UUID) async throws -> Memory? { fail() }
    public func fetchAllMemories() async throws -> [Memory] { fail() }
    public func searchMemories(query: String) async throws -> [Memory] { fail() }
    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)] { fail() }
    public func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] { fail() }
    public func deleteMemory(id: UUID) async throws { fail() }
    public func updateMemory(_ memory: Memory) async throws { fail() }
    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws { fail() }
    public func vacuumMemories(threshold: Double) async throws -> Int { fail() }
    public func saveMessage(_ message: ConversationMessage) async throws { fail() }
    public func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] { fail() }
    public func deleteMessages(for sessionId: UUID) async throws { fail() }
    public func saveSession(_ session: Timeline) async throws { fail() }
    public func fetchSession(id: UUID) async throws -> Timeline? { fail() }
    public func fetchAllSessions(includeArchived: Bool) async throws -> [Timeline] { fail() }
    public func deleteSession(id: UUID) async throws { fail() }
    public func saveJob(_ job: Job) async throws { fail() }
    public func fetchJob(id: UUID) async throws -> Job? { fail() }
    public func fetchAllJobs() async throws -> [Job] { fail() }
    public func fetchJobs(for sessionId: UUID) async throws -> [Job] { fail() }
    public func fetchPendingJobs(limit: Int) async throws -> [Job] { fail() }
    public func deleteJob(id: UUID) async throws { fail() }
    public func monitorJobs() async -> AsyncStream<JobEvent> { fail() }
    public func saveAgent(_ agent: Agent) async throws { fail() }
    public func fetchAgent(id: UUID) async throws -> Agent? { fail() }
    public func fetchAgent(key: String) async throws -> Agent? { fail() }
    public func fetchAllAgents() async throws -> [Agent] { fail() }
    public func hasAgent(id: String) async -> Bool { fail() }
    public func saveWorkspace(_ workspace: WorkspaceReference) async throws { fail() }
    public func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? { fail() }
    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? { fail() }
    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] { fail() }
    public func deleteWorkspace(id: UUID) async throws { fail() }

    public func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws { fail() }
    public func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] { fail() }
    public func fetchClientTools(clientId: UUID) async throws -> [ToolReference] { fail() }
    public func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? { fail() }
    public func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String? { fail() }
}

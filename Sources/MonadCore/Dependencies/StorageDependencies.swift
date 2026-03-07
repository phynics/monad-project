import Dependencies
import Foundation
import MonadShared

// MARK: - Dependency Keys

public typealias FullPersistenceService =
    AgentInstanceStoreProtocol &
    BackgroundJobStoreProtocol &
    ClientStoreProtocol &
    HealthCheckable &
    MSAgentStoreProtocol &
    MemoryStoreProtocol &
    MessageStoreProtocol &
    TimelinePersistenceProtocol &
    ToolPersistenceProtocol &
    WorkspacePersistenceProtocol

public enum PersistenceServiceKey: DependencyKey {
    public static let liveValue: any FullPersistenceService = UnconfiguredPersistenceService()
    public static let testValue: any FullPersistenceService = UnconfiguredPersistenceService()
}

public enum VectorStoreKey: DependencyKey {
    public static let liveValue: (any VectorStoreProtocol)? = nil
}

// MARK: - Dependency Values

public extension DependencyValues {
    var persistenceService: any FullPersistenceService {
        get { self[PersistenceServiceKey.self] }
        set { self[PersistenceServiceKey.self] = newValue }
    }

    var vectorStore: (any VectorStoreProtocol)? {
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

    public func getHealthStatus() async -> HealthStatus {
        .down
    }

    public func getHealthDetails() async -> [String: String]? {
        ["error": "Unconfigured"]
    }

    public func checkHealth() async -> HealthStatus {
        .down
    }

    public func saveMemory(_: Memory, policy _: MemorySavePolicy) async throws -> UUID {
        fail()
    }

    public func fetchMemory(id _: UUID) async throws -> Memory? {
        fail()
    }

    public func fetchAllMemories() async throws -> [Memory] {
        fail()
    }

    public func searchMemories(query _: String) async throws -> [Memory] {
        fail()
    }

    public func searchMemories(embedding _: [Double], limit _: Int, minSimilarity _: Double) async throws -> [(memory: Memory, similarity: Double)] {
        fail()
    }

    public func searchMemories(matchingAnyTag _: [String]) async throws -> [Memory] {
        fail()
    }

    public func deleteMemory(id _: UUID) async throws {
        fail()
    }

    public func updateMemory(_: Memory) async throws {
        fail()
    }

    public func updateMemoryEmbedding(id _: UUID, newEmbedding _: [Double]) async throws {
        fail()
    }

    public func vacuumMemories(threshold _: Double) async throws -> Int {
        fail()
    }

    public func saveMessage(_: ConversationMessage) async throws {
        fail()
    }

    public func fetchMessages(for _: UUID) async throws -> [ConversationMessage] {
        fail()
    }

    public func deleteMessages(for _: UUID) async throws {
        fail()
    }

    public func saveTimeline(_: Timeline) async throws {
        fail()
    }

    public func fetchTimeline(id _: UUID) async throws -> Timeline? {
        fail()
    }

    public func fetchAllTimelines(includeArchived _: Bool) async throws -> [Timeline] {
        fail()
    }

    public func deleteTimeline(id _: UUID) async throws {
        fail()
    }

    public func saveJob(_: BackgroundJob) async throws {
        fail()
    }

    public func fetchJob(id _: UUID) async throws -> BackgroundJob? {
        fail()
    }

    public func fetchAllJobs() async throws -> [BackgroundJob] {
        fail()
    }

    public func fetchJobs(for _: UUID) async throws -> [BackgroundJob] {
        fail()
    }

    public func fetchPendingJobs(limit _: Int) async throws -> [BackgroundJob] {
        fail()
    }

    public func deleteJob(id _: UUID) async throws {
        fail()
    }

    public func monitorJobs() async -> AsyncStream<BackgroundJobEvent> {
        fail()
    }

    public func saveMSAgent(_: MSAgent) async throws {
        fail()
    }

    public func fetchMSAgent(id _: UUID) async throws -> MSAgent? {
        fail()
    }

    public func fetchMSAgent(key _: String) async throws -> MSAgent? {
        fail()
    }

    public func fetchAllMSAgents() async throws -> [MSAgent] {
        fail()
    }

    public func hasMSAgent(id _: String) async -> Bool {
        fail()
    }

    public func saveWorkspace(_: WorkspaceReference) async throws {
        fail()
    }

    public func fetchWorkspace(id _: UUID) async throws -> WorkspaceReference? {
        fail()
    }

    public func fetchWorkspace(id _: UUID, includeTools _: Bool) async throws -> WorkspaceReference? {
        fail()
    }

    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] {
        fail()
    }

    public func deleteWorkspace(id _: UUID) async throws {
        fail()
    }

    public func addToolToWorkspace(workspaceId _: UUID, tool _: ToolReference) async throws {
        fail()
    }

    public func syncTools(workspaceId _: UUID, tools _: [ToolReference]) async throws {
        fail()
    }

    public func fetchTools(forWorkspaces _: [UUID]) async throws -> [ToolReference] {
        fail()
    }

    public func fetchClientTools(clientId _: UUID) async throws -> [ToolReference] {
        fail()
    }

    public func findWorkspaceId(forToolId _: String, in _: [UUID]) async throws -> UUID? {
        fail()
    }

    public func fetchToolSource(toolId _: String, workspaceIds _: [UUID], primaryWorkspaceId _: UUID?) async throws -> String? {
        fail()
    }

    /// AgentInstanceStoreProtocol
    public func saveAgentInstance(_: AgentInstance) async throws {
        fail()
    }

    public func fetchAgentInstance(id _: UUID) async throws -> AgentInstance? {
        fail()
    }

    public func fetchAllAgentInstances() async throws -> [AgentInstance] {
        fail()
    }

    public func deleteAgentInstance(id _: UUID) async throws {
        fail()
    }

    public func fetchTimelines(attachedToAgent _: UUID) async throws -> [Timeline] {
        fail()
    }

    /// ClientStoreProtocol
    public func saveClient(_: ClientIdentity) async throws {
        fail()
    }

    public func fetchClient(id _: UUID) async throws -> ClientIdentity? {
        fail()
    }

    public func fetchAllClients() async throws -> [ClientIdentity] {
        fail()
    }

    public func deleteClient(id _: UUID) async throws -> Bool {
        fail()
    }
}

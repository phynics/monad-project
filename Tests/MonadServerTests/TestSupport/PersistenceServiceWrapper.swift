import Foundation
import MonadCore
import MonadShared
import MonadServer
import GRDB

public final class PersistenceService: HealthCheckable, @unchecked Sendable {
    public let databaseManager: DatabaseManager
    public let workspaceStore: WorkspaceDataRepository
    public let timelineStore: TimelineRepository
    public let memoryStore: MemoryRepository
    public let messageStore: MessageRepository
    public let clientStore: ClientIdentityRepository
    public let toolStore: ToolDataRepository
    public let agentInstanceStore: AgentInstanceDataRepository
    public let msAgentStore: MSAgentRepository
    public let backgroundJobStore: BackgroundJobRepository
    public let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        self.databaseManager = DatabaseManager(dbQueue: dbQueue)
        self.workspaceStore = WorkspaceDataRepository(dbQueue: dbQueue)
        self.timelineStore = TimelineRepository(dbQueue: dbQueue)
        self.memoryStore = MemoryRepository(dbQueue: dbQueue)
        self.messageStore = MessageRepository(dbQueue: dbQueue)
        self.clientStore = ClientIdentityRepository(dbQueue: dbQueue)
        self.toolStore = ToolDataRepository(dbQueue: dbQueue)
        self.agentInstanceStore = AgentInstanceDataRepository(dbQueue: dbQueue)
        self.msAgentStore = MSAgentRepository(dbQueue: dbQueue)
        self.backgroundJobStore = BackgroundJobRepository(dbQueue: dbQueue)
    }

    // MARK: - MemoryStoreProtocol
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID { try await memoryStore.saveMemory(memory, policy: policy) }
    public func fetchMemory(id: UUID) async throws -> Memory? { try await memoryStore.fetchMemory(id: id) }
    public func fetchAllMemories() async throws -> [Memory] { try await memoryStore.fetchAllMemories() }
    public func searchMemories(query: String) async throws -> [Memory] { try await memoryStore.searchMemories(query: query) }
    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(memory: Memory, similarity: Double)] { try await memoryStore.searchMemories(embedding: embedding, limit: limit, minSimilarity: minSimilarity) }
    public func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] { try await memoryStore.searchMemories(matchingAnyTag: tags) }
    public func deleteMemory(id: UUID) async throws { try await memoryStore.deleteMemory(id: id) }
    public func updateMemory(_ memory: Memory) async throws { try await memoryStore.updateMemory(memory) }
    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws { try await memoryStore.updateMemoryEmbedding(id: id, newEmbedding: newEmbedding) }
    public func vacuumMemories(threshold: Double) async throws -> Int { try await memoryStore.vacuumMemories(threshold: threshold) }
    public func pruneMemories(matching query: String, dryRun: Bool) async throws -> Int { try await memoryStore.pruneMemories(matching: query, dryRun: dryRun) }
    public func pruneMemories(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws -> Int { try await memoryStore.pruneMemories(olderThan: timeInterval, dryRun: dryRun) }

    // MARK: - MessageStoreProtocol
    public func saveMessage(_ message: ConversationMessage) async throws { try await messageStore.saveMessage(message) }
    public func fetchMessages(for timelineId: UUID) async throws -> [ConversationMessage] { try await messageStore.fetchMessages(for: timelineId) }
    public func deleteMessages(for timelineId: UUID) async throws { try await messageStore.deleteMessages(for: timelineId) }
    public func pruneMessages(olderThan timeInterval: TimeInterval, dryRun: Bool) async throws -> Int { try await messageStore.pruneMessages(olderThan: timeInterval, dryRun: dryRun) }

    // MARK: - TimelinePersistenceProtocol
    public func saveTimeline(_ timeline: Timeline) async throws { try await timelineStore.saveTimeline(timeline) }
    public func fetchTimeline(id: UUID) async throws -> Timeline? { try await timelineStore.fetchTimeline(id: id) }
    public func fetchAllTimelines(includeArchived: Bool) async throws -> [Timeline] { try await timelineStore.fetchAllTimelines(includeArchived: includeArchived) }
    public func deleteTimeline(id: UUID) async throws { try await timelineStore.deleteTimeline(id: id) }
    public func pruneTimelines(olderThan timeInterval: TimeInterval, excluding excludedTimelineIds: [UUID], dryRun: Bool) async throws -> Int { try await timelineStore.pruneTimelines(olderThan: timeInterval, excluding: excludedTimelineIds, dryRun: dryRun) }

    // MARK: - WorkspacePersistenceProtocol
    public func saveWorkspace(_ workspace: WorkspaceReference) async throws { try await workspaceStore.saveWorkspace(workspace) }
    public func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? { try await workspaceStore.fetchWorkspace(id: id) }
    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? { try await workspaceStore.fetchWorkspace(id: id, includeTools: includeTools) }
    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] { try await workspaceStore.fetchAllWorkspaces() }
    public func deleteWorkspace(id: UUID) async throws { try await workspaceStore.deleteWorkspace(id: id) }

    // MARK: - MSAgentStoreProtocol
    public func saveMSAgent(_ agent: MSAgent) async throws { try await msAgentStore.saveMSAgent(agent) }
    public func fetchMSAgent(id: UUID) async throws -> MSAgent? { try await msAgentStore.fetchMSAgent(id: id) }
    public func fetchMSAgent(key: String) async throws -> MSAgent? { try await msAgentStore.fetchMSAgent(key: key) }
    public func fetchAllMSAgents() async throws -> [MSAgent] { try await msAgentStore.fetchAllMSAgents() }
    public func hasMSAgent(id: String) async -> Bool { await msAgentStore.hasMSAgent(id: id) }

    // MARK: - BackgroundJobStoreProtocol
    public func saveJob(_ job: BackgroundJob) async throws { try await backgroundJobStore.saveJob(job) }
    public func fetchJob(id: UUID) async throws -> BackgroundJob? { try await backgroundJobStore.fetchJob(id: id) }
    public func fetchAllJobs() async throws -> [BackgroundJob] { try await backgroundJobStore.fetchAllJobs() }
    public func fetchJobs(for timelineId: UUID) async throws -> [BackgroundJob] { try await backgroundJobStore.fetchJobs(for: timelineId) }
    public func fetchPendingJobs(limit: Int) async throws -> [BackgroundJob] { try await backgroundJobStore.fetchPendingJobs(limit: limit) }
    public func deleteJob(id: UUID) async throws { try await backgroundJobStore.deleteJob(id: id) }
    public func monitorJobs() async -> AsyncStream<BackgroundJobEvent> { await backgroundJobStore.monitorJobs() }

    // MARK: - AgentInstanceStoreProtocol
    public func saveAgentInstance(_ instance: AgentInstance) async throws { try await agentInstanceStore.saveAgentInstance(instance) }
    public func fetchAgentInstance(id: UUID) async throws -> AgentInstance? { try await agentInstanceStore.fetchAgentInstance(id: id) }
    public func fetchAllAgentInstances() async throws -> [AgentInstance] { try await agentInstanceStore.fetchAllAgentInstances() }
    public func deleteAgentInstance(id: UUID) async throws { try await agentInstanceStore.deleteAgentInstance(id: id) }
    public func fetchTimelines(attachedToAgent agentInstanceId: UUID) async throws -> [Timeline] { try await agentInstanceStore.fetchTimelines(attachedToAgent: agentInstanceId) }

    // MARK: - ClientStoreProtocol
    public func saveClient(_ client: ClientIdentity) async throws { try await clientStore.saveClient(client) }
    public func fetchClient(id: UUID) async throws -> ClientIdentity? { try await clientStore.fetchClient(id: id) }
    public func fetchAllClients() async throws -> [ClientIdentity] { try await clientStore.fetchAllClients() }
    public func deleteClient(id: UUID) async throws -> Bool { try await clientStore.deleteClient(id: id) }

    // MARK: - ToolPersistenceProtocol
    public func addToolToWorkspace(workspaceId: UUID, tool: ToolReference) async throws { try await toolStore.addToolToWorkspace(workspaceId: workspaceId, tool: tool) }
    public func syncTools(workspaceId: UUID, tools: [ToolReference]) async throws { try await toolStore.syncTools(workspaceId: workspaceId, tools: tools) }
    public func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] { try await toolStore.fetchTools(forWorkspaces: workspaceIds) }
    public func fetchClientTools(clientId: UUID) async throws -> [ToolReference] { try await toolStore.fetchClientTools(clientId: clientId) }
    public func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? { try await toolStore.findWorkspaceId(forToolId: toolId, in: workspaceIds) }
    public func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String? { try await toolStore.fetchToolSource(toolId: toolId, workspaceIds: workspaceIds, primaryWorkspaceId: primaryWorkspaceId) }

    public func resetDatabase() async throws {
        // Just recreate the schema or clear things.
        // For testing purposes, we can invoke DB wipe directly, or just rely on new queues.
        try await databaseManager.resetDatabase()
    }
    
    public func getHealthStatus() async -> HealthStatus {
        return await databaseManager.getHealthStatus()
    }

    public func getHealthDetails() async -> [String: String]? {
        return await databaseManager.getHealthDetails()
    }

    public func checkHealth() async -> HealthStatus {
        return await databaseManager.checkHealth()
    }
}

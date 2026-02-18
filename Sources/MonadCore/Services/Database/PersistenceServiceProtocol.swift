import MonadShared
import Foundation
/// Protocol for Persistence Service to enable mocking and isolation
public protocol PersistenceServiceProtocol: HealthCheckable {

    // Memories
    func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID
    func fetchMemory(id: UUID) async throws -> Memory?
    func fetchAllMemories() async throws -> [Memory]
    func searchMemories(query: String) async throws -> [Memory]
    func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(
        memory: Memory, similarity: Double
    )]
    func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory]
    func deleteMemory(id: UUID) async throws
    func updateMemory(_ memory: Memory) async throws
    func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws
    func vacuumMemories(threshold: Double) async throws -> Int


    // Messages
    func saveMessage(_ message: ConversationMessage) async throws
    func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage]
    func deleteMessages(for sessionId: UUID) async throws

    // Sessions
    func saveSession(_ session: ConversationSession) async throws
    func fetchSession(id: UUID) async throws -> ConversationSession?
    func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession]
    func deleteSession(id: UUID) async throws
    // searchArchivedSessions moved to MonadServerCore
    // Prune methods moved to MonadServerCore

    // Jobs
    func saveJob(_ job: Job) async throws
    func fetchJob(id: UUID) async throws -> Job?
    func fetchAllJobs() async throws -> [Job]
    func fetchJobs(for sessionId: UUID) async throws -> [Job]
    func fetchPendingJobs(limit: Int) async throws -> [Job]
    func deleteJob(id: UUID) async throws
    func monitorJobs() async -> AsyncStream<JobEvent>

    // Agents
    func saveAgent(_ agent: Agent) async throws
    func fetchAgent(id: UUID) async throws -> Agent?
    func fetchAgent(key: String) async throws -> Agent? // Support fetching by string key (e.g. "default")
    func fetchAllAgents() async throws -> [Agent]
    func hasAgent(id: String) async -> Bool
    
    // Workspaces
    func saveWorkspace(_ workspace: WorkspaceReference) async throws
    func fetchWorkspace(id: UUID) async throws -> WorkspaceReference?
    /// Fetch workspace with optionally populated tools from the join table
    func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference?
    func fetchAllWorkspaces() async throws -> [WorkspaceReference]
    func deleteWorkspace(id: UUID) async throws

    // Tools
    /// Fetch tools for a list of workspaces
    func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference]
    /// Fetch tools owned by a specific client
    func fetchClientTools(clientId: UUID) async throws -> [ToolReference]
    /// Find which workspace a tool belongs to
    func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID?
    /// Get a display string for the source of a tool (e.g. "Client: Macbook")
    func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String?
    
    // Database Management
    func resetDatabase() async throws
}

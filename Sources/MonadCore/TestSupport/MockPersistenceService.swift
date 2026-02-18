import MonadShared
import Foundation

public final class MockPersistenceService: PersistenceServiceProtocol, @unchecked Sendable, HealthCheckable {
    public var mockHealthStatus: MonadCore.HealthStatus = .ok
    public var mockHealthDetails: [String: String]? = ["mock": "true"]

    public func getHealthStatus() async -> MonadCore.HealthStatus { mockHealthStatus }
    public func getHealthDetails() async -> [String: String]? { mockHealthDetails }

    public func checkHealth() async -> MonadCore.HealthStatus {
        return mockHealthStatus
    }
    
    public var memories: [Memory] = []
    public var searchResults: [(memory: Memory, similarity: Double)] = []
    public var messages: [ConversationMessage] = []
    public var sessions: [ConversationSession] = []
    public var jobs: [Job] = []
    public var workspaces: [WorkspaceReference] = []
    public var agents: [Agent] = []

    public init() {}
    
    // Agents
    public func saveAgent(_ agent: Agent) async throws {
        if let index = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[index] = agent
        } else {
            agents.append(agent)
        }
    }
    
    public func fetchAgent(id: UUID) async throws -> Agent? {
        return agents.first(where: { $0.id == id })
    }
    
    public func fetchAgent(key: String) async throws -> Agent? {
        // Mock implementation assuming key is checked against ID or name?
        // Real implementation uses a "key" column. Here we might assume key==id.uuidString or a specific field?
        // But Agent struct has ID (UUID). Maybe key maps to ID string?
        // Or if key="default", we look for an agent named or ID'd "default"?
        // Agent struct (Step 1514) has ID (UUID).
        // Let's assume key is UUID string for now, or "default" matches a special agent.
        if key == "default" {
            return agents.first // Return first found as default?
        }
        if let uuid = UUID(uuidString: key) {
            return agents.first(where: { $0.id == uuid })
        }
        return nil
    }
    
    public func fetchAllAgents() async throws -> [Agent] {
        return agents
    }
    
    public func hasAgent(id: String) async -> Bool {
        if let uuid = UUID(uuidString: id) {
             return agents.contains(where: { $0.id == uuid })
        }
        return false
    }

    // Memories
    public func saveMemory(_ memory: Memory, policy: MemorySavePolicy) async throws -> UUID {
        memories.append(memory)
        return memory.id
    }

    public func fetchMemory(id: UUID) async throws -> Memory? {
        return memories.first(where: { $0.id == id })
    }

    public func fetchAllMemories() async throws -> [Memory] {
        return memories
    }

    public func searchMemories(query: String) async throws -> [Memory] {
        return memories.filter { $0.title.contains(query) || $0.content.contains(query) }
    }

    public func searchMemories(embedding: [Double], limit: Int, minSimilarity: Double) async throws -> [(
        memory: Memory, similarity: Double
    )] {
        return searchResults
    }

    public func searchMemories(matchingAnyTag tags: [String]) async throws -> [Memory] {
        return memories.filter { memory in
            !Set(memory.tagArray).intersection(tags).isEmpty
        }
    }

    public func deleteMemory(id: UUID) async throws {
        memories.removeAll(where: { $0.id == id })
    }

    public func updateMemory(_ memory: Memory) async throws {
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        }
    }

    public func updateMemoryEmbedding(id: UUID, newEmbedding: [Double]) async throws {
        if let index = memories.firstIndex(where: { $0.id == id }) {
            var memory = memories[index]
            // Mock: Convert embedding to JSON string to simulate storage update
            if let data = try? JSONEncoder().encode(newEmbedding) {
                memory.embedding = String(data: data, encoding: .utf8) ?? ""
                memories[index] = memory
            }
        }
    }

    public func vacuumMemories(threshold: Double) async throws -> Int {
        return 0
    }

    // Messages
    public func saveMessage(_ message: ConversationMessage) async throws {
        messages.append(message)
    }

    public func fetchMessages(for sessionId: UUID) async throws -> [ConversationMessage] {
        return messages.filter { $0.sessionId == sessionId }
    }

    public func deleteMessages(for sessionId: UUID) async throws {
        messages.removeAll(where: { $0.sessionId == sessionId })
    }

    // Sessions
    public func saveSession(_ session: ConversationSession) async throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    public func fetchSession(id: UUID) async throws -> ConversationSession? {
        return sessions.first(where: { $0.id == id })
    }

    public func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession] {
        if includeArchived {
            return sessions
        } else {
            return sessions.filter { !$0.isArchived }
        }
    }

    public func deleteSession(id: UUID) async throws {
        sessions.removeAll(where: { $0.id == id })
    }

    public func searchArchivedSessions(query: String) async throws -> [ConversationSession] {
        return sessions.filter { $0.isArchived && $0.title.contains(query) }
    }

    public func searchArchivedSessions(matchingAnyTag tags: [String]) async throws -> [ConversationSession] {
        return sessions.filter { session in
            session.isArchived && !Set(session.tagArray).intersection(tags).isEmpty
        }
    }

    public func pruneSessions(olderThan timeInterval: TimeInterval, excluding: [UUID] = []) async throws
        -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        let countBefore = sessions.count
        sessions.removeAll { session in
            !session.isArchived && session.updatedAt < cutoffDate && !excluding.contains(session.id)
        }
        return countBefore - sessions.count
    }

    public func pruneMessages(olderThan timeInterval: TimeInterval) async throws -> Int {
        let cutoffDate = Date().addingTimeInterval(-timeInterval)
        let countBefore = messages.count
        messages.removeAll { $0.timestamp < cutoffDate }
        return countBefore - messages.count
    }

    // Jobs
    public func saveJob(_ job: Job) async throws {
        if let index = jobs.firstIndex(where: { $0.id == job.id }) {
            jobs[index] = job
        } else {
            jobs.append(job)
        }
    }

    public func fetchJob(id: UUID) async throws -> Job? {
        return jobs.first(where: { $0.id == id })
    }

    public func fetchAllJobs() async throws -> [Job] {
        return jobs
    }

    public func fetchJobs(for sessionId: UUID) async throws -> [Job] {
        return jobs.filter { $0.sessionId == sessionId }
    }

    public func deleteJob(id: UUID) async throws {
        jobs.removeAll(where: { $0.id == id })
    }

    public func fetchPendingJobs(limit: Int) async throws -> [Job] {
        return Array(jobs.filter { $0.status == .pending }
            .sorted { 
                 if $0.priority != $1.priority { return $0.priority > $1.priority }
                 return $0.createdAt < $1.createdAt
             }
            .prefix(limit))
    }
    
    public func monitorJobs() async -> AsyncStream<JobEvent> {
        return AsyncStream { _ in }
    }

    // Workspaces
    public func saveWorkspace(_ workspace: WorkspaceReference) async throws {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
    }
    
    public func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? {
        return workspaces.first(where: { $0.id == id })
    }
    
    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? {
        // In mock, tools are already in the workspace object
        return workspaces.first(where: { $0.id == id })
    }
    
    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] {
        return workspaces
    }
    
    public func deleteWorkspace(id: UUID) async throws {
        workspaces.removeAll(where: { $0.id == id })
    }

    // Tools
    public func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] {
        let targetWorkspaces = workspaces.filter { workspaceIds.contains($0.id) }
        return targetWorkspaces.flatMap { $0.tools }
    }
    
    public func fetchClientTools(clientId: UUID) async throws -> [ToolReference] {
        let targetWorkspaces = workspaces.filter { $0.ownerId == clientId }
        return targetWorkspaces.flatMap { $0.tools }
    }
    
    public func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? {
        for ws in workspaces where workspaceIds.contains(ws.id) {
            if ws.tools.contains(where: { $0.toolId == toolId }) {
                return ws.id
            }
        }
        return nil
    }
    
    public func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String? {
        guard let wsId = try await findWorkspaceId(forToolId: toolId, in: workspaceIds),
              let ws = workspaces.first(where: { $0.id == wsId })
        else { return nil }
        
        if ws.hostType == .client {
            return "Client Workspace" // Simplified mock response
        } else if ws.id == primaryWorkspaceId {
            return "Primary Workspace"
        } else {
            return "Workspace: \(ws.uri.description)"
        }
    }
    
    // Database Management
    public func resetDatabase() async throws {
        memories.removeAll()
        messages.removeAll()
        sessions.removeAll()
        jobs.removeAll()
        workspaces.removeAll()
    }
}

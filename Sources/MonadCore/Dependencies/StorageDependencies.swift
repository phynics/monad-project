import Dependencies
import Foundation
import MonadShared

// MARK: - Dependency Keys

public enum DatabaseManagerKey: DependencyKey {
    public static let liveValue: any HealthCheckable = UnconfiguredDatabaseManager()
    public static let testValue: any HealthCheckable = UnconfiguredDatabaseManager()
}

public enum AgentInstanceStoreKey: DependencyKey {
    public static let liveValue: any AgentInstanceStoreProtocol = UnconfiguredAgentInstanceStore()
    public static let testValue: any AgentInstanceStoreProtocol = UnconfiguredAgentInstanceStore()
}

public enum ClientStoreKey: DependencyKey {
    public static let liveValue: any ClientStoreProtocol = UnconfiguredClientStore()
    public static let testValue: any ClientStoreProtocol = UnconfiguredClientStore()
}

public enum AgentTemplateStoreKey: DependencyKey {
    public static let liveValue: any AgentTemplateStoreProtocol = UnconfiguredAgentTemplateStore()
    public static let testValue: any AgentTemplateStoreProtocol = UnconfiguredAgentTemplateStore()
}

public enum MemoryStoreKey: DependencyKey {
    public static let liveValue: any MemoryStoreProtocol = UnconfiguredMemoryStore()
    public static let testValue: any MemoryStoreProtocol = UnconfiguredMemoryStore()
}

public enum MessageStoreKey: DependencyKey {
    public static let liveValue: any MessageStoreProtocol = UnconfiguredMessageStore()
    public static let testValue: any MessageStoreProtocol = UnconfiguredMessageStore()
}

public enum TimelinePersistenceKey: DependencyKey {
    public static let liveValue: any TimelinePersistenceProtocol = UnconfiguredTimelinePersistence()
    public static let testValue: any TimelinePersistenceProtocol = UnconfiguredTimelinePersistence()
}

public enum ToolPersistenceKey: DependencyKey {
    public static let liveValue: any ToolPersistenceProtocol = UnconfiguredToolPersistence()
    public static let testValue: any ToolPersistenceProtocol = UnconfiguredToolPersistence()
}

public enum WorkspacePersistenceKey: DependencyKey {
    public static let liveValue: any WorkspacePersistenceProtocol = UnconfiguredWorkspacePersistence()
    public static let testValue: any WorkspacePersistenceProtocol = UnconfiguredWorkspacePersistence()
}

public enum VectorStoreKey: DependencyKey {
    public static let liveValue: (any VectorStoreProtocol)? = nil
}

// MARK: - Dependency Values

public extension DependencyValues {
    var databaseManager: any HealthCheckable {
        get { self[DatabaseManagerKey.self] }
        set { self[DatabaseManagerKey.self] = newValue }
    }

    var agentInstanceStore: any AgentInstanceStoreProtocol {
        get { self[AgentInstanceStoreKey.self] }
        set { self[AgentInstanceStoreKey.self] = newValue }
    }

    var clientStore: any ClientStoreProtocol {
        get { self[ClientStoreKey.self] }
        set { self[ClientStoreKey.self] = newValue }
    }

    var agentTemplateStore: any AgentTemplateStoreProtocol {
        get { self[AgentTemplateStoreKey.self] }
        set { self[AgentTemplateStoreKey.self] = newValue }
    }

    var memoryStore: any MemoryStoreProtocol {
        get { self[MemoryStoreKey.self] }
        set { self[MemoryStoreKey.self] = newValue }
    }

    var messageStore: any MessageStoreProtocol {
        get { self[MessageStoreKey.self] }
        set { self[MessageStoreKey.self] = newValue }
    }

    var timelinePersistence: any TimelinePersistenceProtocol {
        get { self[TimelinePersistenceKey.self] }
        set { self[TimelinePersistenceKey.self] = newValue }
    }

    var toolPersistence: any ToolPersistenceProtocol {
        get { self[ToolPersistenceKey.self] }
        set { self[ToolPersistenceKey.self] = newValue }
    }

    var workspacePersistence: any WorkspacePersistenceProtocol {
        get { self[WorkspacePersistenceKey.self] }
        set { self[WorkspacePersistenceKey.self] = newValue }
    }

    var vectorStore: (any VectorStoreProtocol)? {
        get { self[VectorStoreKey.self] }
        set { self[VectorStoreKey.self] = newValue }
    }
}

// MARK: - Placeholder Implementations

public struct UnconfiguredDatabaseManager: HealthCheckable {
    public init() {}
    private func fail() -> Never {
        fatalError("DatabaseManager not configured.")
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
}

public struct UnconfiguredAgentInstanceStore: AgentInstanceStoreProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("AgentInstanceStore not configured.")
    }

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
}

public struct UnconfiguredClientStore: ClientStoreProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("ClientStore not configured.")
    }

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

    public func fetchClientTools(clientId _: UUID) async throws -> [ToolReference] {
        fail()
    }
}

public struct UnconfiguredAgentTemplateStore: AgentTemplateStoreProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("AgentTemplateStore not configured.")
    }

    public func saveAgentTemplate(_: AgentTemplate) async throws {
        fail()
    }

    public func fetchAgentTemplate(id _: UUID) async throws -> AgentTemplate? {
        fail()
    }

    public func fetchAgentTemplate(key _: String) async throws -> AgentTemplate? {
        fail()
    }

    public func fetchAllAgentTemplates() async throws -> [AgentTemplate] {
        fail()
    }

    public func hasAgentTemplate(id _: String) async -> Bool {
        fail()
    }
}

public struct UnconfiguredMemoryStore: MemoryStoreProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("MemoryStore not configured.")
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

    public func pruneMemories(matching _: String, dryRun _: Bool) async throws -> Int {
        fail()
    }

    public func pruneMemories(olderThan _: TimeInterval, dryRun _: Bool) async throws -> Int {
        fail()
    }
}

public struct UnconfiguredMessageStore: MessageStoreProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("MessageStore not configured.")
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

    public func pruneMessages(olderThan _: TimeInterval, dryRun _: Bool) async throws -> Int {
        fail()
    }
}

public struct UnconfiguredTimelinePersistence: TimelinePersistenceProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("TimelinePersistence not configured.")
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

    public func pruneTimelines(olderThan _: TimeInterval, excluding _: [UUID], dryRun _: Bool) async throws -> Int {
        fail()
    }
}

public struct UnconfiguredToolPersistence: ToolPersistenceProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("ToolPersistence not configured.")
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
}

public struct UnconfiguredWorkspacePersistence: WorkspacePersistenceProtocol {
    public init() {}
    private func fail() -> Never {
        fatalError("WorkspacePersistence not configured.")
    }

    public func saveWorkspace(_: WorkspaceReference) async throws {
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
}

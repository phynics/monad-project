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
    ClientStoreProtocol & 
    ToolPersistenceProtocol & 
    HealthCheckable

public enum PersistenceServiceKey: DependencyKey {
    public static let liveValue: any FullPersistenceService = {
        fatalError("PersistenceService must be configured before use.")
    }()
    public static let testValue: any FullPersistenceService = {
        fatalError("PersistenceService must be provided in tests.")
    }()
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

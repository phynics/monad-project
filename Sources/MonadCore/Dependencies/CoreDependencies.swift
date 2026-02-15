import Dependencies
import Foundation

// MARK: - Dependency Keys

public enum PersistenceServiceKey: DependencyKey {
    public static let liveValue: any PersistenceServiceProtocol = {
        fatalError("PersistenceService must be configured before use.")
    }()
    public static let testValue: any PersistenceServiceProtocol = {
        // You can return a mock here if available in the main target, 
        // or let the test override it.
        fatalError("PersistenceService must be provided in tests.")
    }()
}

public enum LLMServiceKey: DependencyKey {
    public static let liveValue: any LLMServiceProtocol = {
        fatalError("LLMService must be configured before use.")
    }()
}

public enum EmbeddingServiceKey: DependencyKey {
    public static let liveValue: any EmbeddingServiceProtocol = {
        fatalError("EmbeddingService must be configured before use.")
    }()
}

public enum VectorStoreKey: DependencyKey {
    public static let liveValue: (any VectorStoreProtocol)? = nil
}

public enum AgentRegistryKey: DependencyKey {
    public static let liveValue = AgentRegistry()
}

public enum SessionManagerKey: DependencyKey {
    public static let liveValue: SessionManager = {
        fatalError("SessionManager must be configured before use.")
    }()
}

public enum ToolRouterKey: DependencyKey {
    public static let liveValue: ToolRouter = {
        fatalError("ToolRouter must be configured before use.")
    }()
}

public enum ChatOrchestratorKey: DependencyKey {
    public static let liveValue: ChatOrchestrator = {
        fatalError("ChatOrchestrator must be configured before use.")
    }()
}

public enum ReasoningEngineKey: DependencyKey {
    public static let liveValue = ReasoningEngine()
}

// MARK: - Dependency Values

extension DependencyValues {
    public var persistenceService: any PersistenceServiceProtocol {
        get { self[PersistenceServiceKey.self] }
        set { self[PersistenceServiceKey.self] = newValue }
    }

    public var llmService: any LLMServiceProtocol {
        get { self[LLMServiceKey.self] }
        set { self[LLMServiceKey.self] = newValue }
    }

    public var embeddingService: any EmbeddingServiceProtocol {
        get { self[EmbeddingServiceKey.self] }
        set { self[EmbeddingServiceKey.self] = newValue }
    }

    public var vectorStore: (any VectorStoreProtocol)? {
        get { self[VectorStoreKey.self] }
        set { self[VectorStoreKey.self] = newValue }
    }

    public var agentRegistry: AgentRegistry {
        get { self[AgentRegistryKey.self] }
        set { self[AgentRegistryKey.self] = newValue }
    }

    public var sessionManager: SessionManager {
        get { self[SessionManagerKey.self] }
        set { self[SessionManagerKey.self] = newValue }
    }

    public var toolRouter: ToolRouter {
        get { self[ToolRouterKey.self] }
        set { self[ToolRouterKey.self] = newValue }
    }

    public var chatOrchestrator: ChatOrchestrator {
        get { self[ChatOrchestratorKey.self] }
        set { self[ChatOrchestratorKey.self] = newValue }
    }

    public var reasoningEngine: ReasoningEngine {
        get { self[ReasoningEngineKey.self] }
        set { self[ReasoningEngineKey.self] = newValue }
    }
}

extension DependencyValues {
    /// Helper to inject all dependencies from a MonadEngine instance
    public mutating func withEngine(_ engine: MonadEngine) {
        self.persistenceService = engine.persistenceService
        self.llmService = engine.llmService
        self.embeddingService = engine.embeddingService
        self.vectorStore = engine.vectorStore
        self.agentRegistry = engine.agentRegistry
        self.sessionManager = engine.sessionManager
        self.toolRouter = engine.toolRouter
        self.chatOrchestrator = engine.chatOrchestrator
    }
}

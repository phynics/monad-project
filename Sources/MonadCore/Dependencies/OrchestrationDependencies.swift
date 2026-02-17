import MonadShared
import Dependencies
import Foundation

// MARK: - Dependency Keys

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

public enum ChatEngineKey: DependencyKey {
    public static let liveValue: ChatEngine = {
        fatalError("ChatEngine must be configured before use.")
    }()
}

public enum AgentExecutorKey: DependencyKey {
    public static let liveValue = AgentExecutor()
}

// MARK: - Dependency Values

extension DependencyValues {
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

    public var chatEngine: ChatEngine {
        get { self[ChatEngineKey.self] }
        set { self[ChatEngineKey.self] = newValue }
    }

    public var agentExecutor: AgentExecutor {
        get { self[AgentExecutorKey.self] }
        set { self[AgentExecutorKey.self] = newValue }
    }
}

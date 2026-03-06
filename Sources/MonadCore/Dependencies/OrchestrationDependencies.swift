import MonadShared
import Dependencies
import Foundation

// MARK: - Dependency Keys

public enum MSAgentRegistryKey: DependencyKey {
    public static let liveValue = MSAgentRegistry()
}

public enum TimelineManagerKey: DependencyKey {
    public static let liveValue = TimelineManager(
        workspaceRoot: FileManager.default.temporaryDirectory // Default for unconfigured
    )
}

public enum ToolRouterKey: DependencyKey {
    public static let liveValue = ToolRouter()
}

public enum ChatEngineKey: DependencyKey {
    public static let liveValue = ChatEngine()
}

public enum MSAgentExecutorKey: DependencyKey {
    public static let liveValue = MSAgentExecutor(
        persistenceService: UnconfiguredPersistenceService(),
        chatEngine: ChatEngine()
    )
}

// MARK: - Dependency Values

extension DependencyValues {
    public var msAgentRegistry: MSAgentRegistry {
        get { self[MSAgentRegistryKey.self] }
        set { self[MSAgentRegistryKey.self] = newValue }
    }

    public var timelineManager: TimelineManager {
        get { self[TimelineManagerKey.self] }
        set { self[TimelineManagerKey.self] = newValue }
    }

    public var toolRouter: ToolRouter {
        get { self[ToolRouterKey.self] }
        set { self[ToolRouterKey.self] = newValue }
    }

    public var chatEngine: ChatEngine {
        get { self[ChatEngineKey.self] }
        set { self[ChatEngineKey.self] = newValue }
    }

    public var msAgentExecutor: MSAgentExecutor {
        get { self[MSAgentExecutorKey.self] }
        set { self[MSAgentExecutorKey.self] = newValue }
    }
}

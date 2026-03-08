import Dependencies
import Foundation
import MonadShared

// MARK: - Dependency Keys

public enum AgentTemplateRegistryKey: DependencyKey {
    public static let liveValue = AgentTemplateRegistry()
}

public enum WorkspaceManagerKey: DependencyKey {
    public static let liveValue = WorkspaceManager(
        repository: WorkspaceRepository(),
        workspaceCreator: NullWorkspaceCreator()
    )
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

public enum AgentTemplateExecutorKey: DependencyKey {
    public static let liveValue = AgentTemplateExecutor(
        backgroundJobStore: UnconfiguredBackgroundJobStore(),
        messageStore: UnconfiguredMessageStore(),
        chatEngine: ChatEngine()
    )
}

public enum AgentInstanceManagerKey: DependencyKey {
    public static let liveValue = AgentInstanceManager(
        workspaceRoot: FileManager.default.temporaryDirectory // Default for unconfigured
    )
}

// MARK: - Dependency Values

public extension DependencyValues {
    var agentTemplateRegistry: AgentTemplateRegistry {
        get { self[AgentTemplateRegistryKey.self] }
        set { self[AgentTemplateRegistryKey.self] = newValue }
    }

    var workspaceManager: WorkspaceManager {
        get { self[WorkspaceManagerKey.self] }
        set { self[WorkspaceManagerKey.self] = newValue }
    }

    var timelineManager: TimelineManager {
        get { self[TimelineManagerKey.self] }
        set { self[TimelineManagerKey.self] = newValue }
    }

    var toolRouter: ToolRouter {
        get { self[ToolRouterKey.self] }
        set { self[ToolRouterKey.self] = newValue }
    }

    var chatEngine: ChatEngine {
        get { self[ChatEngineKey.self] }
        set { self[ChatEngineKey.self] = newValue }
    }

    var agentTemplateExecutor: AgentTemplateExecutor {
        get { self[AgentTemplateExecutorKey.self] }
        set { self[AgentTemplateExecutorKey.self] = newValue }
    }

    var agentInstanceManager: AgentInstanceManager {
        get { self[AgentInstanceManagerKey.self] }
        set { self[AgentInstanceManagerKey.self] = newValue }
    }
}

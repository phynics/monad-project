import Dependencies
import Foundation
import MonadShared

// MARK: - Dependency Keys

public enum AgentWorkspaceServiceKey: DependencyKey {
    public static var liveValue: AgentWorkspaceService {
        preconditionFailure(
            "AgentWorkspaceService requires an explicit workspaceRoot. " +
                "Configure it via MonadServerFactory or your test setup."
        )
    }

    public static let testValue = AgentWorkspaceService(
        workspaceRoot: FileManager.default.temporaryDirectory
    )
}

public enum WorkspaceManagerKey: DependencyKey {
    public static var liveValue: WorkspaceManager {
        @Dependency(\.agentWorkspaceService) var service
        return WorkspaceManager(
            repository: service,
            workspaceCreator: NullWorkspaceCreator()
        )
    }
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

public enum AgentInstanceManagerKey: DependencyKey {
    public static var liveValue: AgentInstanceManager {
        @Dependency(\.agentWorkspaceService) var service
        return AgentInstanceManager(repository: service)
    }
}

public enum ChatTurnPluginsKey: DependencyKey {
    public static let liveValue: [any ChatTurnPlugin] = []
    public static let testValue: [any ChatTurnPlugin] = []
}

// MARK: - Dependency Values

public extension DependencyValues {
    var agentWorkspaceService: AgentWorkspaceService {
        get { self[AgentWorkspaceServiceKey.self] }
        set { self[AgentWorkspaceServiceKey.self] = newValue }
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

    var agentInstanceManager: AgentInstanceManager {
        get { self[AgentInstanceManagerKey.self] }
        set { self[AgentInstanceManagerKey.self] = newValue }
    }

    var chatTurnPlugins: [any ChatTurnPlugin] {
        get { self[ChatTurnPluginsKey.self] }
        set { self[ChatTurnPluginsKey.self] = newValue }
    }
}

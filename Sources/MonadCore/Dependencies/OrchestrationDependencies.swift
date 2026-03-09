import Dependencies
import Foundation
import MonadShared

// MARK: - Dependency Keys

public enum WorkspaceRepositoryKey: DependencyKey {
    public static let liveValue = WorkspaceRepository(
        workspaceRoot: FileManager.default.temporaryDirectory
    )
}

public enum WorkspaceManagerKey: DependencyKey {
    public static var liveValue: WorkspaceManager {
        @Dependency(\.workspaceRepository) var repository
        return WorkspaceManager(
            repository: repository,
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
        @Dependency(\.workspaceRepository) var repository
        return AgentInstanceManager(repository: repository)
    }
}

// MARK: - Dependency Values

public extension DependencyValues {
    var workspaceRepository: WorkspaceRepository {
        get { self[WorkspaceRepositoryKey.self] }
        set { self[WorkspaceRepositoryKey.self] = newValue }
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
}

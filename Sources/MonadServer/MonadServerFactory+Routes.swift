import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import PositronicKit
import PKShared
import MonadShared
import ServiceLifecycle
import UnixSignals

@available(macOS 14.0, *)
extension MonadServerFactory {
    struct RouteDependencies {
        let memoryStore: any MemoryStoreProtocol
        let messageStore: any MessageStoreProtocol
        let timelineStore: any TimelinePersistenceProtocol
        let workspaceStore: any WorkspaceStore
        let toolStore: any ToolPersistenceProtocol
        let agentTemplateStore: any AgentTemplateStoreProtocol
        let requestOriginStore: any RequestOriginStoreProtocol
        let workspaceManager: any WorkspaceResolver
        let timelineManager: TimelineManager
        let toolRouter: ToolRouter
        let databaseManager: any HealthCheckable
        let llmService: any LLMStreamClient & LLMConfigStore & LLMUtilityClient & HealthCheckable
    }

    // MARK: - Route Registration

    static func registerPublicRoutes(
        on router: Router<AppRequestContext>,
        databaseManager: any HealthCheckable,
        llmService: any LLMStreamClient & LLMConfigStore & LLMUtilityClient & HealthCheckable
    ) {
        router.get("/health") { _, _ -> String in
            return "OK"
        }

        let startTime = Date()
        let statusController = StatusAPIController<AppRequestContext>(
            databaseManager: databaseManager,
            llmService: llmService,
            startTime: startTime
        )
        statusController.addRoutes(to: router)

        router.get("/") { _, _ -> String in
            return "Monad Server is running."
        }
    }

    static func registerProtectedGroup(
        on router: Router<AppRequestContext>
    ) -> RouterGroup<AppRequestContext> {
        let apiKey = ProcessInfo.processInfo.environment["MONAD_API_KEY"] ?? "monad-secret"
        let protected = router.group("/api")
            .add(middleware: AuthMiddleware(token: apiKey))

        protected.get("/test") { _, _ -> String in
            return "Authenticated!"
        }

        return protected
    }

    static func registerChatAndTimelineRoutes(
        on protected: RouterGroup<AppRequestContext>,
        connectionManager: WebSocketConnectionManager,
        chat: PositronicKit,
        timelineManager: TimelineManager,
        timelineStore: any TimelinePersistenceProtocol,
        workspaceStore: any WorkspaceStore,
        agentInstanceStore: any AgentInstanceStoreProtocol,
        toolRouter: ToolRouter,
        verbose: Bool
    ) {
        let wsController = WebSocketAPIController<AppRequestContext>(connectionManager: connectionManager)
        wsController.addRoutes(to: protected)

        let timelineController = TimelineAPIController<AppRequestContext>(
            timelineManager: timelineManager,
            timelineStore: timelineStore,
            workspaceStore: workspaceStore
        )
        timelineController.addRoutes(to: protected.group("/sessions"))

        let chatController = ChatAPIController<AppRequestContext>(
            chat: chat,
            timelineManager: timelineManager,
            agentInstanceStore: agentInstanceStore,
            toolRouter: toolRouter,
            verbose: verbose
        )
        chatController.addRoutes(to: protected.group("/sessions"))
    }

    static func registerResourceRoutes(
        on protected: RouterGroup<AppRequestContext>,
        dependencies: RouteDependencies,
        agentInstanceManager: any AgentInstanceManagerProtocol,
    ) {
        let memoryController = MemoryAPIController<AppRequestContext>(
            timelineManager: dependencies.timelineManager,
            memoryStore: dependencies.memoryStore
        )
        memoryController.addRoutes(to: protected.group("/memories"))

        let pruneController = PruneAPIController<AppRequestContext>(
            memoryStore: dependencies.memoryStore,
            timelineStore: dependencies.timelineStore,
            messageStore: dependencies.messageStore
        )
        pruneController.addRoutes(to: protected.group("/prune"))

        let toolController = ToolAPIController<AppRequestContext>(
            timelineManager: dependencies.timelineManager,
            timelineStore: dependencies.timelineStore,
            messageStore: dependencies.messageStore,
            toolRouter: dependencies.toolRouter
        )
        toolController.addRoutes(to: protected.group("/tools"))

        let agentTemplateController = AgentTemplateAPIController<AppRequestContext>(
            agentTemplateStore: dependencies.agentTemplateStore
        )
        agentTemplateController.addRoutes(to: protected.group("/agentTemplates"))

        let agentInstanceController = AgentInstanceAPIController<AppRequestContext>(
            agentInstanceManager: agentInstanceManager
        )
        agentInstanceController.addRoutes(to: protected.group("/agents"))

        let workspaceAPIController = WorkspaceAPIController<AppRequestContext>(
            workspaceStore: dependencies.workspaceStore,
            toolStore: dependencies.toolStore
        )
        workspaceAPIController.addRoutes(to: protected.group("/workspaces"))

        let filesController = FilesAPIController<AppRequestContext>(
            workspaceManager: dependencies.workspaceManager
        )
        filesController.addRoutes(to: protected.group("/workspaces/:workspaceId/files"))

        let clientController = ClientAPIController<AppRequestContext>(
            requestOriginStore: dependencies.requestOriginStore,
            workspaceStore: dependencies.workspaceStore,
            toolStore: dependencies.toolStore
        )
        clientController.addRoutes(to: protected.group("/clients"))

        let configController = ConfigurationAPIController<AppRequestContext>(llmService: dependencies.llmService)
        configController.addRoutes(to: protected.group("/config"))
    }

    // MARK: - Service Group

    static func buildServiceGroup(
        router: Router<AppRequestContext>,
        hostname: String,
        port: Int,
        orphanCleanup: OrphanCleanupService,
        logger: Logger
    ) -> ServiceGroup {
        let app = Application(
            router: router,
            server: .http1WebSocketUpgrade(webSocketRouter: router, configuration: .init()),
            configuration: .init(address: .hostname(hostname, port: port))
        )

        logger.info("Server starting on \(hostname):\(port)")

        let bonjourAdvertiser = BonjourAdvertiser(port: port)

        return ServiceGroup(
            configuration: ServiceGroupConfiguration(
                services: [
                    .init(service: app),
                    .init(service: orphanCleanup),
                    .init(service: bonjourAdvertiser),
                ],
                gracefulShutdownSignals: [UnixSignal.sigterm, UnixSignal.sigint],
                logger: logger
            )
        )
    }
}

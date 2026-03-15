import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import MonadCore
import MonadShared
import ServiceLifecycle
import UnixSignals

@available(macOS 14.0, *)
extension MonadServerFactory {
    // MARK: - Route Registration

    static func registerPublicRoutes(on router: Router<AppRequestContext>) {
        router.get("/health") { _, _ -> String in
            return "OK"
        }

        let startTime = Date()
        let statusController = StatusAPIController<AppRequestContext>(startTime: startTime)
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
        verbose: Bool
    ) {
        let wsController = WebSocketAPIController<AppRequestContext>(connectionManager: connectionManager)
        wsController.addRoutes(to: protected)

        let timelineController = TimelineAPIController<AppRequestContext>()
        timelineController.addRoutes(to: protected.group("/sessions"))

        let chatController = ChatAPIController<AppRequestContext>(verbose: verbose)
        chatController.addRoutes(to: protected.group("/sessions"))
    }

    static func registerResourceRoutes(
        on protected: RouterGroup<AppRequestContext>,
        agentInstanceManager: AgentInstanceManager,
        llmService: LLMService
    ) {
        let memoryController = MemoryAPIController<AppRequestContext>()
        memoryController.addRoutes(to: protected.group("/memories"))

        let pruneController = PruneAPIController<AppRequestContext>()
        pruneController.addRoutes(to: protected.group("/prune"))

        let toolController = ToolAPIController<AppRequestContext>()
        toolController.addRoutes(to: protected.group("/tools"))

        let agentTemplateController = AgentTemplateAPIController<AppRequestContext>()
        agentTemplateController.addRoutes(to: protected.group("/agentTemplates"))

        let agentInstanceController = AgentInstanceAPIController<AppRequestContext>(
            agentInstanceManager: agentInstanceManager
        )
        agentInstanceController.addRoutes(to: protected.group("/agents"))

        let workspaceAPIController = WorkspaceAPIController<AppRequestContext>()
        workspaceAPIController.addRoutes(to: protected.group("/workspaces"))

        let filesController = FilesAPIController<AppRequestContext>()
        filesController.addRoutes(to: protected.group("/workspaces/:workspaceId/files"))

        let clientController = ClientAPIController<AppRequestContext>()
        clientController.addRoutes(to: protected.group("/clients"))

        let configController = ConfigurationAPIController<AppRequestContext>(llmService: llmService)
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
                    .init(service: bonjourAdvertiser)
                ],
                gracefulShutdownSignals: [UnixSignal.sigterm, UnixSignal.sigint],
                logger: logger
            )
        )
    }
}

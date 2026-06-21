import Foundation
import GRDB
import Hummingbird
import HummingbirdWebSocket
import Logging
import MonadShared
import PKLocalEmbeddings
import PKShared
import PositronicKit
import ServiceLifecycle
import UnixSignals

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

@available(macOS 14.0, *)
public struct MonadServerFactory {
    public typealias AppRequestContext = BasicWebSocketRequestContext

    public struct ServerContext {
        public let serviceGroup: ServiceGroup
    }

    /// Aggregates all initialized stores, services, and managers needed for server startup
    private struct ServerComponents {
        let databaseManager: DatabaseManager
        let repositories: RepositorySet
        let services: ServiceSet
        let managers: ManagerSet
        let orphanCleanup: OrphanCleanupService
    }

    private struct RepositorySet {
        let agentInstanceStore: AgentInstanceDataRepository
        let requestOriginStore: RequestOriginRepository
        let agentTemplateStore: AgentTemplateRepository
        let memoryStore: MemoryRepository
        let messageStore: MessageRepository
        let timelinePersistence: TimelineRepository
        let toolPersistence: ToolDataRepository
        let workspacePersistence: WorkspaceDataRepository
    }

    private struct ServiceSet {
        let llmService: any LLMServiceProtocol
        let embeddingService: any EmbeddingServiceProtocol
        let vectorStore: (any VectorStoreProtocol)?
        let keyValueStore: DatabaseKeyValueStore
        let connectionManager: WebSocketConnectionManager
    }

    private struct ManagerSet {
        let timelineManager: TimelineManager
        let toolRouter: ToolRouter
        let agentInstanceManager: any AgentInstanceManagerProtocol
        let workspaceManager: any WorkspaceManagerProtocol
    }

    public static func createServerContext(
        hostname: String = "127.0.0.1",
        port: Int = 8080,
        verbose: Bool = false,
        logger: Logger = Logger.module(named: "server")
    ) async throws -> ServerContext {
        let components = try await initializeComponents(logger: logger)

        let router = Router(context: AppRequestContext.self)
        router.add(middleware: LogMiddleware())
        router.add(middleware: ErrorMiddleware())

        let coreChat = PositronicKitCore(
            llmService: components.services.llmService,
            persistence: .init(
                messageStore: components.repositories.messageStore,
                timelinePersistence: components.repositories.timelinePersistence,
                workspacePersistence: components.repositories.workspacePersistence,
                memoryStore: components.repositories.memoryStore,
                toolPersistence: components.repositories.toolPersistence,
                agentInstanceStore: components.repositories.agentInstanceStore,
                requestOriginStore: components.repositories.requestOriginStore,
                agentTemplateStore: components.repositories.agentTemplateStore
            ),
            embeddingService: components.services.embeddingService,
            timelineManager: components.managers.timelineManager,
            toolRouter: components.managers.toolRouter
        )

        registerPublicRoutes(
            on: router,
            databaseManager: components.databaseManager,
            llmService: components.services.llmService
        )
        let protected = registerProtectedGroup(on: router)
        registerChatAndTimelineRoutes(
            on: protected,
            connectionManager: components.services.connectionManager,
            chat: coreChat,
            timelineManager: components.managers.timelineManager,
            timelineStore: components.repositories.timelinePersistence,
            workspaceStore: components.repositories.workspacePersistence,
            agentInstanceStore: components.repositories.agentInstanceStore,
            toolRouter: components.managers.toolRouter,
            verbose: verbose
        )
        registerResourceRoutes(
            on: protected,
            dependencies: .init(
                memoryStore: components.repositories.memoryStore,
                messageStore: components.repositories.messageStore,
                timelineStore: components.repositories.timelinePersistence,
                workspaceStore: components.repositories.workspacePersistence,
                toolStore: components.repositories.toolPersistence,
                agentTemplateStore: components.repositories.agentTemplateStore,
                requestOriginStore: components.repositories.requestOriginStore,
                workspaceManager: components.managers.workspaceManager,
                timelineManager: components.managers.timelineManager,
                toolRouter: components.managers.toolRouter,
                databaseManager: components.databaseManager,
                llmService: components.services.llmService
            ),
            agentInstanceManager: components.managers.agentInstanceManager
        )

        let serviceGroup = buildServiceGroup(
            router: router, hostname: hostname, port: port,
            orphanCleanup: components.orphanCleanup, logger: logger
        )

        return ServerContext(serviceGroup: serviceGroup)
    }

    // MARK: - Component Initialization

    private static func initializeComponents(logger: Logger) async throws -> ServerComponents {
        let databaseManager: DatabaseManager
        do {
            databaseManager = try DatabaseManager.create(onInitializationFailure: { error, databasePath in
                offerDatabaseReset(error: error, databasePath: databasePath, logger: logger)
            })
            logger.info("Database initialized.")
        } catch {
            logger.error("Failed to initialize database: \(error)")
            throw error
        }

        let repositories = initializeRepositories(dbQueue: databaseManager.dbQueue)
        let services = try await initializeServices(
            dbQueue: databaseManager.dbQueue, logger: logger
        )
        let workspaceRoot = try defaultWorkspacePath()

        let managers = initializeManagers(
            repositories: repositories,
            workspaceRoot: workspaceRoot,
            connectionManager: services.connectionManager
        )

        let orphanCleanup = OrphanCleanupService(
            workspaceRoot: workspaceRoot,
            workspaceStore: repositories.workspacePersistence,
            timelineStore: repositories.timelinePersistence
        )

        return ServerComponents(
            databaseManager: databaseManager,
            repositories: repositories,
            services: services,
            managers: managers,
            orphanCleanup: orphanCleanup
        )
    }

    private static func offerDatabaseReset(error: any Error, databasePath: String, logger: Logger) -> Bool {
        guard isatty(STDIN_FILENO) != 0 else {
            logger.error(
                "Database initialization failed for \(databasePath). Run in an interactive terminal to allow resetting the database. Error: \(error)"
            )
            return false
        }

        print("")
        print("Database initialization failed for \(databasePath).")
        print("Error: \(error.localizedDescription)")
        print("Reset the database and start over? This will delete the local server database. [y/N]: ", terminator: "")

        guard let response = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        let shouldReset = response == "y" || response == "yes"
        if shouldReset {
            logger.warning("Resetting database after initialization failure at \(databasePath)")
        }
        return shouldReset
    }

    private static func initializeRepositories(dbQueue: DatabaseQueue) -> RepositorySet {
        RepositorySet(
            agentInstanceStore: AgentInstanceDataRepository(dbQueue: dbQueue),
            requestOriginStore: RequestOriginRepository(dbQueue: dbQueue),
            agentTemplateStore: AgentTemplateRepository(dbQueue: dbQueue),
            memoryStore: MemoryRepository(dbQueue: dbQueue),
            messageStore: MessageRepository(dbQueue: dbQueue),
            timelinePersistence: TimelineRepository(dbQueue: dbQueue),
            toolPersistence: ToolDataRepository(dbQueue: dbQueue),
            workspacePersistence: WorkspaceDataRepository(dbQueue: dbQueue)
        )
    }

    private static func initializeServices(
        dbQueue: DatabaseQueue,
        logger: Logger
    ) async throws -> ServiceSet {
        LLMProviderBootstrap.registerBuiltIns()

        let embeddingService: any EmbeddingServiceProtocol = LocalEmbeddingService()
        logger.info("Using Local Embedding Service")

        var vectorStore: (any VectorStoreProtocol)?
        do {
            vectorStore = try VectorStore()
            try await vectorStore?.initialize()
            logger.info("Vector Store initialized.")
        } catch {
            logger.error("Failed to initialize Vector Store: \(error). No fallback available.")
            vectorStore = nil
        }

        let appSupportDir = try defaultWorkspacePath().deletingLastPathComponent()
        let configURL = appSupportDir.appendingPathComponent("config.json")
        let storage = ConfigurationStorage(configURL: configURL)
        await storage.migrateIfNeeded()
        let llmService = LLMService(storage: storage)
        await llmService.loadConfiguration()

        return ServiceSet(
            llmService: llmService,
            embeddingService: embeddingService,
            vectorStore: vectorStore,
            keyValueStore: DatabaseKeyValueStore(dbQueue: dbQueue),
            connectionManager: WebSocketConnectionManager()
        )
    }

    private static func initializeManagers(
        repositories: RepositorySet,
        workspaceRoot: URL,
        connectionManager: WebSocketConnectionManager
    ) -> ManagerSet {
        let agentWorkspaceService = AgentWorkspaceService(
            workspaceRoot: workspaceRoot,
            workspacePersistence: repositories.workspacePersistence
        )
        let timelineManager = TimelineManager(
            stores: .init(
                timelineStore: repositories.timelinePersistence,
                messageStore: repositories.messageStore,
                workspaceStore: repositories.workspacePersistence,
                toolPersistence: repositories.toolPersistence
            ),
            workspaceRoot: workspaceRoot,
            workspaceCreator: WorkspaceFactory(connectionManager: connectionManager)
        )
        let toolRouter = ToolRouter(
            timelineManager: timelineManager,
            messageStore: repositories.messageStore
        )

        return ManagerSet(
            timelineManager: timelineManager,
            toolRouter: toolRouter,
            agentInstanceManager: AgentInstanceManager(
                repository: agentWorkspaceService,
                stores: .init(
                    instanceStore: repositories.agentInstanceStore,
                    timelineStore: repositories.timelinePersistence,
                    messageStore: repositories.messageStore,
                    workspaceStore: repositories.workspacePersistence
                )
            ),
            workspaceManager: WorkspaceManager(
                repository: agentWorkspaceService,
                workspaceCreator: WorkspaceFactory(connectionManager: connectionManager)
            )
        )
    }

    /// Default workspace path
    private static func defaultWorkspacePath() throws -> URL {
        let fileManager = FileManager.default
        let appName = "Monad"

        #if os(macOS)
            guard
                let appSupport = fileManager.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first
            else {
                // Fallback
                let home = fileManager.homeDirectoryForCurrentUser
                let workspacesDir = home.appendingPathComponent(
                    ".monad/workspaces", isDirectory: true
                )
                try? fileManager.createDirectory(
                    at: workspacesDir, withIntermediateDirectories: true
                )
                return workspacesDir
            }

            let appDir = appSupport.appendingPathComponent(appName, isDirectory: true)
            let workspacesDir = appDir.appendingPathComponent("Workspaces", isDirectory: true)
            try fileManager.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
            return workspacesDir

        #elseif os(Linux)
            let env = ProcessInfo.processInfo.environment
            let dataHome: URL
            if let xdgData = env["XDG_DATA_HOME"] {
                dataHome = URL(fileURLWithPath: xdgData)
            } else {
                dataHome = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local")
                    .appendingPathComponent("share")
            }

            let appDir = dataHome.appendingPathComponent(appName.lowercased(), isDirectory: true)
            let workspacesDir = appDir.appendingPathComponent("workspaces", isDirectory: true)
            try fileManager.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
            return workspacesDir

        #else
            // Fallback
            let home = fileManager.homeDirectoryForCurrentUser
            let workspacesDir = home.appendingPathComponent(".monad/workspaces", isDirectory: true)
            try fileManager.createDirectory(at: workspacesDir, withIntermediateDirectories: true)
            return workspacesDir
        #endif
    }
}

import Dependencies
import Foundation
import GRDB
import Hummingbird
import HummingbirdWebSocket
import Logging
import MonadCore
import MonadShared
import ServiceLifecycle
import UnixSignals

@available(macOS 14.0, *)
public struct MonadServerFactory {
    public typealias AppRequestContext = BasicWebSocketRequestContext

    public struct ServerContext {
        public let serviceGroup: ServiceGroup
        public let dependencies: DependencyValues
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
        let clientStore: ClientIdentityRepository
        let agentTemplateStore: AgentTemplateRepository
        let memoryStore: MemoryRepository
        let messageStore: MessageRepository
        let timelinePersistence: TimelineRepository
        let toolPersistence: ToolDataRepository
        let workspacePersistence: WorkspaceDataRepository
    }

    private struct ServiceSet {
        let llmService: LLMService
        let embeddingService: any EmbeddingServiceProtocol
        let vectorStore: any VectorStoreProtocol
        let keyValueStore: DatabaseKeyValueStore
        let connectionManager: WebSocketConnectionManager
    }

    private struct ManagerSet {
        let timelineManager: TimelineManager
        let toolRouter: ToolRouter
        let chatEngine: ChatEngine
        let agentInstanceManager: AgentInstanceManager
        let workspaceManager: WorkspaceManager
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

        return try await withDependencies {
            configureDependencies(&$0, from: components)
        } operation: {
            registerPublicRoutes(on: router)
            let protected = registerProtectedGroup(on: router)
            registerChatAndTimelineRoutes(
                on: protected,
                connectionManager: components.services.connectionManager,
                verbose: verbose
            )
            registerResourceRoutes(
                on: protected,
                agentInstanceManager: components.managers.agentInstanceManager,
                llmService: components.services.llmService
            )

            let serviceGroup = buildServiceGroup(
                router: router, hostname: hostname, port: port,
                orphanCleanup: components.orphanCleanup, logger: logger
            )

            return ServerContext(
                serviceGroup: serviceGroup,
                dependencies: DependencyValues._current
            )
        }
    }

    // MARK: - Component Initialization

    private static func initializeComponents(logger: Logger) async throws -> ServerComponents {
        let databaseManager: DatabaseManager
        do {
            databaseManager = try DatabaseManager.create()
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
            workspaceRoot: workspaceRoot,
            connectionManager: services.connectionManager
        )

        let orphanCleanup = OrphanCleanupService(workspaceRoot: workspaceRoot)

        return ServerComponents(
            databaseManager: databaseManager,
            repositories: repositories,
            services: services,
            managers: managers,
            orphanCleanup: orphanCleanup
        )
    }

    private static func initializeRepositories(dbQueue: DatabaseQueue) -> RepositorySet {
        RepositorySet(
            agentInstanceStore: AgentInstanceDataRepository(dbQueue: dbQueue),
            clientStore: ClientIdentityRepository(dbQueue: dbQueue),
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
        let embeddingService: any EmbeddingServiceProtocol
        let envVars = ProcessInfo.processInfo.environment
        if let apiKey = envVars["MONAD_OPENAI_API_KEY"] ?? envVars["OPENAI_API_KEY"],
           !apiKey.isEmpty {
            embeddingService = OpenAIEmbeddingService(apiKey: apiKey)
            logger.info("Using OpenAI Embedding Service")
        } else {
            embeddingService = LocalEmbeddingService()
            logger.info("Using Local Embedding Service (OpenAI API Key not found)")
        }

        var vectorStore: any VectorStoreProtocol
        do {
            vectorStore = try VectorStore()
            try await vectorStore.initialize()
            logger.info("Vector Store initialized.")
        } catch {
            logger.error("Failed to initialize Vector Store: \(error). Falling back to mock.")
            vectorStore = MockVectorStore()
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
        workspaceRoot: URL,
        connectionManager: WebSocketConnectionManager
    ) -> ManagerSet {
        let agentWorkspaceService = AgentWorkspaceService(workspaceRoot: workspaceRoot)

        return ManagerSet(
            timelineManager: TimelineManager(
                workspaceRoot: workspaceRoot,
                connectionManager: connectionManager,
                workspaceCreator: WorkspaceFactory()
            ),
            toolRouter: ToolRouter(),
            chatEngine: ChatEngine(),
            agentInstanceManager: AgentInstanceManager(repository: agentWorkspaceService),
            workspaceManager: WorkspaceManager(
                repository: agentWorkspaceService,
                connectionManager: connectionManager,
                workspaceCreator: WorkspaceFactory()
            )
        )
    }

    // MARK: - Dependency Configuration

    private static func configureDependencies(
        _ deps: inout DependencyValues,
        from components: ServerComponents
    ) {
        let repos = components.repositories
        deps.databaseManager = components.databaseManager
        deps.agentInstanceStore = repos.agentInstanceStore
        deps.clientStore = repos.clientStore
        deps.agentTemplateStore = repos.agentTemplateStore
        deps.memoryStore = repos.memoryStore
        deps.messageStore = repos.messageStore
        deps.timelinePersistence = repos.timelinePersistence
        deps.toolPersistence = repos.toolPersistence
        deps.workspacePersistence = repos.workspacePersistence

        let svcs = components.services
        deps.llmService = svcs.llmService
        deps.embeddingService = svcs.embeddingService
        deps.vectorStore = svcs.vectorStore
        deps.keyValueStore = svcs.keyValueStore

        let mgrs = components.managers
        deps.timelineManager = mgrs.timelineManager
        deps.toolRouter = mgrs.toolRouter
        deps.chatEngine = mgrs.chatEngine
        deps.agentInstanceManager = mgrs.agentInstanceManager
        deps.workspaceManager = mgrs.workspaceManager
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

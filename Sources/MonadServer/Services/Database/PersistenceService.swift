import MonadShared
import MonadCore
import Foundation
import GRDB
import Logging



/// Thread-safe persistence service using GRDB
public actor PersistenceService: PersistenceServiceProtocol, HealthCheckable {
    public nonisolated let dbQueue: DatabaseQueue
    internal let logger = Logger.database
    
    // Job Event Stream
    private let jobStream: AsyncStream<JobEvent>
    private let jobContinuation: AsyncStream<JobEvent>.Continuation

    // MARK: - HealthCheckable

    public func getHealthStatus() async -> MonadCore.HealthStatus {
        // Actor-isolated, but we can assume ok if initialized. 
        // We'll return ok and let checkHealth do the real work if needed.
        return .ok
    }

    public func getHealthDetails() async -> [String: String]? {
        return ["path": dbQueue.path]
    }

    public func checkHealth() async -> MonadCore.HealthStatus {
        do {
            try await dbQueue.read { db in
                _ = try Int.fetchOne(db, sql: "SELECT 1")
            }
            return .ok
        } catch {
            logger.error("Database health check failed: \(error)")
            return .down
        }
    }

    // MARK: - Initialization

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        let (stream, continuation) = AsyncStream.makeStream(of: JobEvent.self)
        self.jobStream = stream
        self.jobContinuation = continuation
    }
    
    public func monitorJobs() -> AsyncStream<JobEvent> {
        return jobStream
    }

    internal func emit(_ event: JobEvent) {
        jobContinuation.yield(event)
    }

    public nonisolated var databaseWriter: DatabaseWriter {
        return dbQueue
    }

    public static func create(path: String? = nil) throws -> PersistenceService {
        let databasePath: String
        if let providedPath = path {
            databasePath = providedPath
        } else {
            databasePath = try Self.defaultDatabasePath()
        }

        let queue = try DatabaseQueue(path: databasePath)
        try Self.performMigration(on: queue)
        let service = PersistenceService(dbQueue: queue)

        // Initial sync
        Task {
            try? await service.syncTableDirectory()
        }

        return service
    }

    /// Default database path
    private static func defaultDatabasePath() throws -> String {
        let fileManager = FileManager.default
        let appName = "Monad"
        let filename = "monad.sqlite"

        #if os(macOS)
            // ~/Library/Application Support/Monad/monad.sqlite
            guard
                let appSupport = fileManager.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first
            else {
                throw PersistenceServiceError.applicationSupportNotFound
            }
            let dir = appSupport.appendingPathComponent(appName)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(filename).path

        #elseif os(Linux)
            // XDG_DATA_HOME or ~/.local/share/monad/monad.sqlite
            let env = ProcessInfo.processInfo.environment
            let dataHome: URL
            if let xdgData = env["XDG_DATA_HOME"] {
                dataHome = URL(fileURLWithPath: xdgData)
            } else {
                dataHome = fileManager.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local")
                    .appendingPathComponent("share")
            }

            let dir = dataHome.appendingPathComponent(appName.lowercased())
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent(filename).path
        #endif
    }

    // MARK: - Migrations

    private static func performMigration(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
    }

    // MARK: - Database Reset

    /// Reset the database (clears non-immutable data)
    public func resetDatabase() throws {
        try dbQueue.write { db in
            // Memory is used for recall and injected opportunistically,
            // it can be reset as it's not part of the protected 'Archive'.
            try Memory.deleteAll(db)
            try Job.deleteAll(db)

            // Note: Archives and conversationMessage/Session are now protected by triggers
            // and cannot be deleted or modified (for archived sessions).
            // We do not attempt to delete them here to avoid trigger violations.
            logger.info(
                "Database reset: Memories cleared. Archives preserved due to immutability constraints."
            )
        }
    }

    /// Synchronize table_directory with actual SQLite schema
    public func syncTableDirectory() async throws {
        try await dbQueue.write { db in
            // Get current tables from SQLite master (excluding internal tables and the directory itself)
            let currentTables = try String.fetchAll(
                db,
                sql: """
                        SELECT name FROM sqlite_master 
                        WHERE type='table' 
                        AND name NOT LIKE 'sqlite_%' 
                        AND name NOT LIKE 'grdb_%'
                        AND name != 'table_directory'
                    """)

            // Remove tables that no longer exist
            try db.execute(
                sql: """
                        DELETE FROM table_directory 
                        WHERE name NOT IN (\(currentTables.map { "'\($0)'" }.joined(separator: ",")))
                    """)

            // Add new tables
            let now = Date()
            for table in currentTables {
                let exists =
                    try Int.fetchOne(
                        db, sql: "SELECT COUNT(*) FROM table_directory WHERE name = ?",
                        arguments: [table]) ?? 0
                if exists == 0 {
                    try db.execute(
                        sql:
                            "INSERT INTO table_directory (name, description, createdAt) VALUES (?, ?, ?)",
                        arguments: [table, "", now])
                }
            }
        }
    }
    // MARK: - Agents
    
    public func saveAgent(_ agent: Agent) async throws {
        try await dbQueue.write { db in
            try agent.save(db)
        }
    }
    
    public func fetchAgent(id: UUID) async throws -> Agent? {
        try await dbQueue.read { db in
            try Agent.fetchOne(db, key: id)
        }
    }
    
    public func fetchAgent(key: String) async throws -> Agent? {
         try await dbQueue.read { db in
             // Try to parse UUID first, if fails assume it's a key lookup if widely supported, 
             // but Agent primary key is UUID. 
             // If 'key' is meant to be 'id' string:
             if let uuid = UUID(uuidString: key) {
                 return try Agent.fetchOne(db, key: uuid)
             }
             // Fallback: maybe we want to search by name? Or if we had a string ID.
             // For now, return nil if not UUID, as Agent.id is UUID.
             return nil
         }
    }
    
    public func fetchAllAgents() async throws -> [Agent] {
        try await dbQueue.read { db in
            try Agent.fetchAll(db)
        }
    }
    
    public func hasAgent(id: String) async -> Bool {
        guard let uuid = UUID(uuidString: id) else { return false }
        return await (try? dbQueue.read { db in
            try Agent.exists(db, key: uuid)
        }) ?? false
    }

    // MARK: - Workspaces
    
    public func saveWorkspace(_ workspace: WorkspaceReference) async throws {
        try await dbQueue.write { db in
            try workspace.save(db)
        }
    }
    
    public func fetchWorkspace(id: UUID) async throws -> WorkspaceReference? {
        try await dbQueue.read { db in
            try WorkspaceReference.fetchOne(db, key: id)
        }
    }
    
    public func fetchAllWorkspaces() async throws -> [WorkspaceReference] {
        try await dbQueue.read { db in
            try WorkspaceReference.fetchAll(db)
        }
    }
    
    public func deleteWorkspace(id: UUID) async throws {
        _ = try await dbQueue.write { db in
             try WorkspaceReference.deleteOne(db, key: id)
        }
    }
    
    // MARK: - Advanced Tool Queries
    
    public func fetchWorkspace(id: UUID, includeTools: Bool) async throws -> WorkspaceReference? {
        try await dbQueue.read { db in
            guard let workspace = try WorkspaceReference.fetchOne(db, key: id) else {
                return nil
            }
            
            if includeTools {
                // Load associated tools from WorkspaceTool table (Join)
                let workspaceTools = try WorkspaceTool
                    .filter(Column("workspaceId") == id)
                    .fetchAll(db)
                
                let toolRefs = workspaceTools.compactMap { try? $0.toToolReference() }
                
                // Create a new workspace with the tools populated
                return WorkspaceReference(
                    id: workspace.id,
                    uri: workspace.uri,
                    hostType: workspace.hostType,
                    ownerId: workspace.ownerId,
                    tools: toolRefs,
                    rootPath: workspace.rootPath,
                    trustLevel: workspace.trustLevel,
                    lastModifiedBy: workspace.lastModifiedBy,
                    status: workspace.status,
                    createdAt: workspace.createdAt
                )
            }
            return workspace
        }
    }

    public func fetchTools(forWorkspaces workspaceIds: [UUID]) async throws -> [ToolReference] {
         guard !workspaceIds.isEmpty else { return [] }
         return try await dbQueue.read { db in
            let tools = try WorkspaceTool
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)
            return try tools.map { try $0.toToolReference() }
         }
    }
    
    public func fetchClientTools(clientId: UUID) async throws -> [ToolReference] {
        return try await dbQueue.read { db in
            let workspaces = try WorkspaceReference
                .filter(Column("ownerId") == clientId)
                .fetchAll(db)
            
            let workspaceIds = workspaces.map { $0.id }
            guard !workspaceIds.isEmpty else { return [] }

            let tools = try WorkspaceTool
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchAll(db)

            return try tools.map { try $0.toToolReference() }
        }
    }

    public func findWorkspaceId(forToolId toolId: String, in workspaceIds: [UUID]) async throws -> UUID? {
        try await dbQueue.read { db in
            let exists = try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db)
            return exists?.workspaceId
        }
    }

    public func fetchToolSource(toolId: String, workspaceIds: [UUID], primaryWorkspaceId: UUID?) async throws -> String? {
        if workspaceIds.isEmpty { return nil }
        return try await dbQueue.read { db -> String? in
            if let toolRecord = try WorkspaceTool
                .filter(Column("toolId") == toolId)
                .filter(workspaceIds.contains(Column("workspaceId")))
                .fetchOne(db),
                let ws = try WorkspaceReference.fetchOne(db, key: toolRecord.workspaceId)
            {
                if ws.hostType == .client {
                    if let owner = ws.ownerId,
                        let client = try? ClientIdentity.fetchOne(db, key: owner)
                    {
                        return "Client: \(client.hostname)"
                    }
                    return "Client Workspace"
                } else if primaryWorkspaceId == ws.id {
                    return "Primary Workspace"
                } else {
                    return "Workspace: \(ws.uri.description)"
                }
            }
            return nil
        }
    }

    // Prune methods moved to MonadServerCore
}

// MARK: - Errors

public enum PersistenceServiceError: LocalizedError {
    case applicationSupportNotFound

    public var errorDescription: String? {
        switch self {
        case .applicationSupportNotFound:
            return "Could not find Application Support directory"
        }
    }
}


import Foundation
import GRDB
import Logging

public enum JobEvent: Sendable {
    case jobUpdated(Job)
    case jobDeleted(UUID)
}

/// Thread-safe persistence service using GRDB
public actor PersistenceService: PersistenceServiceProtocol, HealthCheckable {
    public nonisolated let dbQueue: DatabaseQueue
    internal let logger = Logger.database
    
    // Job Event Stream
    private let jobStream: AsyncStream<JobEvent>
    private let jobContinuation: AsyncStream<JobEvent>.Continuation

    // MARK: - HealthCheckable

    public var healthStatus: HealthStatus {
        get async {
            // Actor-isolated, but we can assume ok if initialized. 
            // We'll return ok and let checkHealth do the real work if needed.
            return .ok
        }
    }

    public var healthDetails: [String: String]? {
        get async {
            return ["path": dbQueue.path]
        }
    }

    public func checkHealth() async -> HealthStatus {
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


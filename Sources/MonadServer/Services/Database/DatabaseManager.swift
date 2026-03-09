import MonadCore
import MonadShared
import Foundation
import GRDB
import ErrorKit
import Logging

/// Core Database Manager that owns the SQLite connection and handles migrations.
public actor DatabaseManager: HealthCheckable {
    public let dbQueue: DatabaseQueue
    private let logger = Logger.module(named: "database")

    // MARK: - Initialization

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public static func create(path: String? = nil) throws -> DatabaseManager {
        let databasePath: String
        if let providedPath = path {
            databasePath = providedPath
        } else {
            databasePath = try Self.defaultDatabasePath()
        }

        let queue = try DatabaseQueue(path: databasePath)
        try Self.performMigration(on: queue)
        let manager = DatabaseManager(dbQueue: queue)

        // Initial sync
        Task {
            try? await manager.syncTableDirectory()
        }

        return manager
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
                throw DatabaseManagerError.applicationSupportNotFound
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
            try Memory.deleteAll(db)
            try BackgroundJob.deleteAll(db)

            logger.info(
                "Database reset: Memories cleared. Archives preserved due to immutability constraints."
            )
        }
    }

    /// Synchronize table_directory with actual SQLite schema
    public func syncTableDirectory() async throws {
        try await dbQueue.write { db in
            let currentTables = try String.fetchAll(
                db,
                sql: """
                        SELECT name FROM sqlite_master
                        WHERE type='table'
                        AND name NOT LIKE 'sqlite_%'
                        AND name NOT LIKE 'grdb_%'
                        AND name != 'table_directory'
                    """)

            let placeholders = currentTables.map { _ in "?" }.joined(separator: ",")
            try db.execute(
                sql: "DELETE FROM table_directory WHERE name NOT IN (\(placeholders))",
                arguments: StatementArguments(currentTables))

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

    // MARK: - HealthCheckable

    public func getHealthStatus() async -> HealthStatus {
        return .ok
    }

    public func getHealthDetails() async -> [String: String]? {
        return ["path": dbQueue.path]
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
}

public enum DatabaseManagerError: Throwable {
    case applicationSupportNotFound

    public var errorDescription: String? {
        switch self {
        case .applicationSupportNotFound:
            return "Could not find Application Support directory"
        }
    }

    public var userFriendlyMessage: String {
        switch self {
        case .applicationSupportNotFound:
            return "The Monad server could not find a suitable location on your system to store its database."
        }
    }
}

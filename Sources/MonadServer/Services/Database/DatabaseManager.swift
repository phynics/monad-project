import ErrorKit
import Foundation
import GRDB
import Logging
import PositronicKit
import PKShared
import MonadShared

/// Core Database Manager that owns the SQLite connection and handles migrations.
public actor DatabaseManager: HealthCheckable {
    public let dbQueue: DatabaseQueue
    private let logger = Logger.module(named: "database")

    // MARK: - Initialization

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public static func create(
        path: String? = nil,
        onInitializationFailure: ((any Error, String) -> Bool)? = nil
    ) throws -> DatabaseManager {
        let databasePath: String
        if let providedPath = path {
            databasePath = providedPath
        } else {
            databasePath = try Self.defaultDatabasePath()
        }

        let queue: DatabaseQueue
        do {
            queue = try Self.openDatabase(at: databasePath)
        } catch {
            guard Self.isResettableInitializationFailure(error),
                onInitializationFailure?(error, databasePath) == true
            else {
                throw error
            }

            try Self.removeDatabaseFiles(at: databasePath)
            queue = try Self.openDatabase(at: databasePath)
        }

        return DatabaseManager(dbQueue: queue)
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

    private static func openDatabase(at databasePath: String) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: databasePath)
        try Self.performMigration(on: queue)
        return queue
    }

    private static func performMigration(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
    }

    private static func removeDatabaseFiles(at databasePath: String) throws {
        let fileManager = FileManager.default
        for path in [databasePath, "\(databasePath)-shm", "\(databasePath)-wal"] {
            if fileManager.fileExists(atPath: path) {
                try fileManager.removeItem(atPath: path)
            }
        }
    }

    private static func isResettableInitializationFailure(_ error: any Error) -> Bool {
        guard let databaseError = error as? GRDB.DatabaseError else {
            return false
        }

        switch databaseError.resultCode {
        case .SQLITE_CORRUPT, .SQLITE_NOTADB, .SQLITE_CONSTRAINT:
            return true
        default:
            return false
        }
    }

    // MARK: - Database Reset

    /// Reset the database (clears non-immutable data)
    public func resetDatabase() throws {
        try dbQueue.write { db in
            try Memory.deleteAll(db)

            logger.info(
                "Database reset: Memories cleared. Archives preserved due to immutability constraints."
            )
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

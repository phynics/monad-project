import Foundation
import GRDB
import Logging

/// Thread-safe persistence service using GRDB
public actor PersistenceService: PersistenceServiceProtocol {
    public nonisolated let dbQueue: DatabaseQueue
    internal let logger = Logger.database

    // MARK: - Initialization

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
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

            // Note: Notes and conversationMessage/Session are now protected by triggers
            // and cannot be deleted or modified (for archived sessions).
            // We do not attempt to delete them here to avoid trigger violations.
            logger.info(
                "Database reset: Memories cleared. Notes and Archives preserved due to immutability constraints."
            )
        }
    }

    /// Execute raw SQL and return results as JSON-compatible dictionaries
    public func executeRaw(sql: String, arguments: [DatabaseValue]) async throws -> [[String:
        AnyCodable]]
    {
        let results: [[String: AnyCodable]] = try await dbQueue.write { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
            return rows.map { row in
                var dict: [String: AnyCodable] = [:]
                for (column, value) in row {
                    // Convert DatabaseValue to JSON-compatible type
                    let jsonValue: Any
                    if value.isNull {
                        jsonValue = NSNull()
                    } else if let dateValue = Date.fromDatabaseValue(value) {
                        jsonValue = ISO8601DateFormatter().string(from: dateValue)
                    } else if let intValue = Int64.fromDatabaseValue(value) {
                        jsonValue = Int(intValue)
                    } else if let doubleValue = Double.fromDatabaseValue(value) {
                        jsonValue = doubleValue
                    } else if let boolValue = Bool.fromDatabaseValue(value) {
                        jsonValue = boolValue
                    } else if let stringValue = String.fromDatabaseValue(value) {
                        jsonValue = stringValue
                    } else if let dataValue = Data.fromDatabaseValue(value) {
                        // For blobs (like UUIDs), convert to string or hex if possible
                        if dataValue.count == 16,
                            let uuid = UUID(
                                uuidString: dataValue.map { String(format: "%02hhx", $0) }.joined())
                        {
                            jsonValue = uuid.uuidString
                        } else {
                            jsonValue = dataValue.base64EncodedString()
                        }
                    } else {
                        jsonValue = value.description
                    }
                    dict[column] = AnyCodable(jsonValue)
                }
                return dict
            }
        }

        // Sync table directory after potential schema changes
        if sql.lowercased().contains("create table") || sql.lowercased().contains("drop table") {
            try await syncTableDirectory()
        }

        return results
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

public enum NoteError: LocalizedError {
    case noteIsReadonly

    public var errorDescription: String? {
        switch self {
        case .noteIsReadonly:
            return "Cannot delete readonly note"
        }
    }
}

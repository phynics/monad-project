import Foundation
import GRDB
import OSLog

/// Thread-safe persistence service using GRDB
public actor PersistenceService: PersistenceServiceProtocol {
    internal let dbQueue: DatabaseQueue
    internal let logger = Logger.database

    // MARK: - Initialization

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
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
        return PersistenceService(dbQueue: queue)
    }

    /// Default database path in Application Support
    private static func defaultDatabasePath() throws -> String {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PersistenceServiceError.applicationSupportNotFound
        }
        
        let appDir = appSupport.appendingPathComponent("MonadAssistant", isDirectory: true)
        try fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("monad.sqlite").path
    }

    // MARK: - Migrations

    private static func performMigration(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)
    }

    // MARK: - Database Reset

    /// Reset the entire database (deletes all data)
    public func resetDatabase() throws {
        try dbQueue.write { db in
            try ConversationMessage.deleteAll(db)
            try ConversationSession.deleteAll(db)
            try Memory.deleteAll(db)
            try Note.deleteAll(db)
            try DatabaseSchema.createDefaultNotes(in: db)
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

import Foundation
import GRDB
import MonadCore

/// A GRDB-backed implementation of `KeyValueStoreProtocol`, backed by a `key_value_store` table.
public actor DatabaseKeyValueStore: KeyValueStoreProtocol {
    private let dbQueue: DatabaseQueue

    public init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    public func value(forKey key: String) async throws -> Data? {
        try await dbQueue.read { db in
            try Data.fetchOne(
                db,
                sql: "SELECT value FROM key_value_store WHERE key = ?",
                arguments: [key]
            )
        }
    }

    public func setValue(_ value: Data?, forKey key: String) async throws {
        try await dbQueue.write { db in
            if let value {
                try db.execute(
                    sql: """
                    INSERT INTO key_value_store (key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                    arguments: [key, value]
                )
            } else {
                try db.execute(
                    sql: "DELETE FROM key_value_store WHERE key = ?",
                    arguments: [key]
                )
            }
        }
    }

    public func allKeys() async throws -> [String] {
        try await dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT key FROM key_value_store")
        }
    }
}

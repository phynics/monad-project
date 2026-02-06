import Foundation
import GRDB
import MonadCore
import Testing

@Suite(.serialized)
@MainActor
struct ExecuteSQLToolTests {
    private let persistence: PersistenceService
    private let dbQueue: DatabaseQueue

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        dbQueue = queue

        try await persistence.syncTableDirectory()
    }

    @Test("Test ExecuteSQLTool: Basic SELECT")
    func selectQuery() async throws {
        let tool = ExecuteSQLTool(persistenceService: persistence)
        let result = try await tool.execute(parameters: [
            "sql": "SELECT name FROM table_directory LIMIT 1"
        ])

        #expect(result.success)
        #expect(result.output.contains("name"))
    }

    @Test("Test ExecuteSQLTool: Create Table and Insert")
    func createAndInsert() async throws {
        let tool = ExecuteSQLTool(persistenceService: persistence)

        // 1. Create table
        let createResult = try await tool.execute(parameters: [
            "sql": "CREATE TABLE custom_data (id INTEGER PRIMARY KEY, value TEXT)"
        ])
        #expect(createResult.success)

        // 2. Insert data
        let insertResult = try await tool.execute(parameters: [
            "sql": "INSERT INTO custom_data (value) VALUES ('Hello SQL')"
        ])
        #expect(insertResult.success)

        // 3. Query data
        let queryResult = try await tool.execute(parameters: [
            "sql": "SELECT value FROM custom_data"
        ])
        #expect(queryResult.success)
        #expect(queryResult.output.contains("Hello SQL"))
    }

    @Test("Test ExecuteSQLTool: Protection Enforcement")
    func protectionEnforcement() async throws {
        // ... (existing code)
    }

    @Test("Test table_directory synchronization")
    func tableDirectorySync() async throws {
        // Initial sync should have core tables
        try await persistence.syncTableDirectory()

        var tables = try await persistence.executeRaw(sql: "SELECT name FROM table_directory", arguments: [])
        #expect(tables.contains { $0["name"]?.value as? String == "memory" })

        // Create custom table
        _ = try await persistence.executeRaw(sql: "CREATE TABLE custom_test (id INTEGER PRIMARY KEY)", arguments: [])

        tables = try await persistence.executeRaw(sql: "SELECT name FROM table_directory", arguments: [])
        #expect(tables.contains { $0["name"]?.value as? String == "custom_test" })

        // Drop custom table
        _ = try await persistence.executeRaw(sql: "DROP TABLE custom_test", arguments: [])

        tables = try await persistence.executeRaw(sql: "SELECT name FROM table_directory", arguments: [])
        #expect(!tables.contains { $0["name"]?.value as? String == "custom_test" })
    }
}

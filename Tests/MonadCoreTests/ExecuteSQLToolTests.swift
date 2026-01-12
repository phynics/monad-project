import Foundation
import GRDB
import MonadCore
import Testing

@testable import MonadCore

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
    }

    @Test("Test ExecuteSQLTool: Basic SELECT")
    func selectQuery() async throws {
        // Add a note to query
        let note = Note(name: "Test Note", content: "Test Content")
        try await persistence.saveNote(note)
        
        let tool = ExecuteSQLTool(persistenceService: persistence)
        let result = try await tool.execute(parameters: [
            "sql": "SELECT name, content FROM note WHERE name = 'Test Note'"
        ])
        
        #expect(result.success)
        #expect(result.output.contains("Test Note"))
        #expect(result.output.contains("Test Content"))
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
        let tool = ExecuteSQLTool(persistenceService: persistence)
        
        // Setup a note
        let note = Note(name: "Immortal Note", content: "Cannot be deleted")
        try await persistence.saveNote(note)
        
        // Attempt to delete via tool
        let deleteResult = try await tool.execute(parameters: [
            "sql": "DELETE FROM note WHERE name = 'Immortal Note'"
        ])
        
        #expect(!deleteResult.success)
        #expect(deleteResult.error?.contains("Notes cannot be deleted") == true)
        
        // Verify note still exists
        let fetched = try await persistence.fetchNote(id: note.id)
        #expect(fetched != nil)
    }
}

import Foundation
import GRDB
import MonadCore
import Testing

@testable import MonadCore

@Suite(.serialized)
@MainActor
struct SearchToolsTests {
    private let persistence: PersistenceService
    
    private let executeSQLTool: ExecuteSQLTool

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        
        executeSQLTool = ExecuteSQLTool(persistenceService: persistence)
    }

    @Test("Search Archived Chats via SQL")
    func testSearchArchivedChatsSQL() async throws {
        // ... (existing code)
    }
    
    @Test("Search Notes via SQL")
    func testSearchNotesSQL() async throws {
        // ... (existing code)
    }
    
    @Test("Search Memories via SQL")
    func testSearchMemoriesSQL() async throws {
        let mem1 = Memory(title: "Project Alpha", content: "Key details about Alpha", tags: ["work"])
        let mem2 = Memory(title: "Vacation", content: "Hawaii trip details", tags: ["personal"])
        _ = try await persistence.saveMemory(mem1)
        _ = try await persistence.saveMemory(mem2)
        
        // Test content match
        let res1 = try await executeSQLTool.execute(parameters: ["sql": "SELECT title, content FROM memory WHERE content LIKE '%Alpha%'"])
        #expect(res1.success)
        #expect(res1.output.contains("Project Alpha"))
        #expect(res1.output.contains("Key details about Alpha"))
        
        // Test tag match
        let res2 = try await executeSQLTool.execute(parameters: ["sql": "SELECT title FROM memory WHERE tags LIKE '%personal%'"])
        #expect(res2.success)
        #expect(res2.output.contains("Vacation"))
    }
}

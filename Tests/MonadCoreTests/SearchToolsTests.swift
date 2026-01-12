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
    private let searchMemoriesTool: SearchMemoriesTool
    private let mockEmbeddingService: MockEmbeddingService

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        
        mockEmbeddingService = MockEmbeddingService()

        executeSQLTool = ExecuteSQLTool(persistenceService: persistence)
        searchMemoriesTool = SearchMemoriesTool(persistenceService: persistence, embeddingService: mockEmbeddingService)
    }

    @Test("Search Archived Chats via SQL")
    func testSearchArchivedChatsSQL() async throws {
        // Setup data
        var session1 = ConversationSession(title: "SwiftUI Project")
        session1.isArchived = true
        try await persistence.saveSession(session1)
        
        var session2 = ConversationSession(title: "Python Script")
        session2.isArchived = true
        try await persistence.saveSession(session2)
        
        // Active session
        let session3 = ConversationSession(title: "Active SwiftUI")
        try await persistence.saveSession(session3)
        
        // Test search via SQL
        let result = try await executeSQLTool.execute(parameters: [
            "sql": "SELECT title FROM conversationSession WHERE isArchived = 1 AND title LIKE '%SwiftUI%'"
        ])
        
        #expect(result.success)
        #expect(result.output.contains("SwiftUI Project"))
        #expect(!result.output.contains("Python Script"))
        #expect(!result.output.contains("Active SwiftUI"))
    }
    
    @Test("Search Notes via SQL")
    func testSearchNotesSQL() async throws {
        let note1 = Note(name: "Meeting Notes", content: "Discussed Q1 goals")
        let note2 = Note(name: "Shopping List", content: "Milk, Eggs")
        try await persistence.saveNote(note1)
        try await persistence.saveNote(note2)
        
        let result = try await executeSQLTool.execute(parameters: [
            "sql": "SELECT name FROM note WHERE content LIKE '%goals%'"
        ])
        
        #expect(result.success)
        #expect(result.output.contains("Meeting Notes"))
        #expect(!result.output.contains("Shopping List"))
    }
    
    @Test("Search Memories")
    func testSearchMemories() async throws {
        let mem1 = Memory(title: "Project Alpha", content: "Key details about Alpha", tags: ["work"])
        let mem2 = Memory(title: "Vacation", content: "Hawaii trip details", tags: ["personal"])
        _ = try await persistence.saveMemory(mem1)
        _ = try await persistence.saveMemory(mem2)
        
        // Test content match
        let res1 = try await searchMemoriesTool.execute(parameters: ["query": "Alpha"])
        #expect(res1.success)
        #expect(res1.output.contains("Project Alpha"))
        #expect(res1.output.contains("ID: \(mem1.id.uuidString)"))
        #expect(res1.output.contains("Key details about Alpha"))
        
        // Test tag match
        let res2 = try await searchMemoriesTool.execute(parameters: ["query": "personal"])
        #expect(res2.success)
        #expect(res2.output.contains("Vacation"))
        #expect(res2.output.contains("ID: \(mem2.id.uuidString)"))
        #expect(res2.output.contains("Hawaii trip details"))
        
        // Test no match
        let res3 = try await searchMemoriesTool.execute(parameters: ["query": "Mars"])
        #expect(res3.success)
        #expect(res3.output.contains("No memories found"))
    }
    
    @Test("Search Memories with results")
    func testSearchMemoriesWithResults() async throws {
        let mem1Content = "Swift is a powerful and intuitive programming language for iOS and macOS."
        let m1 = Memory(title: "Swift Programming", content: mem1Content, tags: ["tech"])
        
        _ = try await persistence.saveMemory(m1)
        
        // Use exact match to ensure keyword search catches it
        let result = try await searchMemoriesTool.execute(parameters: ["query": "Swift Programming"])
        
        #expect(result.success)
        #expect(result.output.contains("Swift Programming"))
    }
}

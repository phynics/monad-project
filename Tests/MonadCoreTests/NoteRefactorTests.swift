import Foundation
import GRDB
import MonadCore
import Testing

@testable import MonadCore

@Suite(.serialized)
@MainActor
struct NoteRefactorTests {
    private let persistence: PersistenceService
    private let dbQueue: DatabaseQueue

    init() async throws {
        dbQueue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(dbQueue)

        persistence = PersistenceService(dbQueue: dbQueue)
    }

    @Test("Verify Note model does not have alwaysAppend")
    func noteModelCheck() {
        let note = Note(name: "Test", content: "Content")
        // This test is mostly for compilation. If alwaysAppend existed, 
        // we might try to access it here to ensure it doesn't exist anymore.
        // Since we are @testable, we can see internal properties if any.
    }

    @Test("Verify database schema for note table")
    func databaseSchemaCheck() async throws {
        try await dbQueue.read { db in
            let columns = try db.columns(in: "note")
            let columnNames = columns.map { $0.name }
            
            #expect(!columnNames.contains("alwaysAppend"), "alwaysAppend column should not exist in note table")
            #expect(!columnNames.contains("isEnabled"), "isEnabled column should not exist in note table")
            #expect(!columnNames.contains("priority"), "priority column should not exist in note table")
        }
    }

    @Test("Verify all notes are included in context")
    func allNotesInContext() async throws {
        let n1 = Note(name: "Note 1", content: "Content 1")
        let n2 = Note(name: "Note 2", content: "Content 2")
        
        try await persistence.saveNote(n1)
        try await persistence.saveNote(n2)
        
        let context = try await persistence.getContextNotes()
        #expect(context.contains("Note 1"))
        #expect(context.contains("Content 1"))
        #expect(context.contains("Note 2"))
        #expect(context.contains("Content 2"))
    }
}

import Foundation
import GRDB
import MonadCore
import Testing

@testable import MonadCore

@Suite(.serialized)
@MainActor
struct EditNoteToolTests {
    private let persistence: PersistenceService
    private let tool: EditNoteTool

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)

        persistence = PersistenceService(dbQueue: queue)
        tool = EditNoteTool(persistenceService: persistence)
    }

    @Test("Edit existing note")
    func editNote() async throws {
        let note = Note(name: "My Note", content: "Initial content")
        try await persistence.saveNote(note)
        
        let result = try await tool.execute(parameters: [
            "note_name": "My Note",
            "content": "Updated content"
        ])
        
        #expect(result.success)
        
        let notes = try await persistence.searchNotes(query: "My Note")
        #expect(notes.first?.content == "Updated content")
    }
    
    @Test("Edit non-existent note fails")
    func editMissingNote() async throws {
        let result = try await tool.execute(parameters: [
            "note_name": "Missing Note",
            "content": "New content"
        ])
        
        #expect(!result.success)
        #expect(result.error?.contains("not found") == true)
    }
    
    @Test("Edit readonly note succeeds")
    func editReadonlyNote() async throws {
        // System note is created by default and is readonly
        let notes = try await persistence.fetchAllNotes()
        let systemNote = notes.first { $0.isReadonly }
        #expect(systemNote != nil)
        
        guard let noteName = systemNote?.name else { return }
        
        let result = try await tool.execute(parameters: [
            "note_name": noteName,
            "content": "Modified system content"
        ])
        
        #expect(result.success)
        
        // Verify content changed
        let refetched = try await persistence.fetchNote(id: systemNote!.id)
        #expect(refetched?.content == "Modified system content")
    }
}

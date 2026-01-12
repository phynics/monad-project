import Foundation
import MonadCore

extension PersistenceManager {
    public func saveNote(_ note: Note) async throws {
        try await persistence.saveNote(note)
    }

    public func fetchNote(id: UUID) async throws -> Note? {
        try await persistence.fetchNote(id: id)
    }

    public func fetchAllNotes() async throws -> [Note] {
        try await persistence.fetchAllNotes()
    }

    public func searchNotes(query: String) async throws -> [Note] {
        try await persistence.searchNotes(query: query)
    }

    public func deleteNote(id: UUID) async throws {
        try await persistence.deleteNote(id: id)
    }

    public func getContextNotes() async throws -> String {
        try await persistence.getContextNotes()
    }
}

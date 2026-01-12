import Foundation
import GRPC
import MonadCore
import SwiftProtobuf

final class NoteHandler: MonadNoteServiceAsyncProvider {
    private let persistence: PersistenceServiceProtocol
    
    init(persistence: PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    func fetchAllNotes(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadNoteList {
        let notes = try await persistence.fetchAllNotes()
        var response = MonadNoteList()
        response.notes = notes.map { $0.toProto() }
        return response
    }
    
    func saveNote(request: MonadNote, context: GRPCAsyncServerCallContext) async throws -> MonadNote {
        let note = Note(from: request)
        try await persistence.saveNote(note)
        return note.toProto()
    }
    
    func deleteNote(request: MonadDeleteNoteRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteNote(id: uuid)
        return MonadEmpty()
    }
}
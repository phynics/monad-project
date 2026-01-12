import Foundation
import GRPC
import SwiftProtobuf

public final class NoteHandler: MonadNoteServiceAsyncProvider, Sendable {
    private let persistence: any PersistenceServiceProtocol
    
    public init(persistence: any PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    public func fetchAllNotes(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadNoteList {
        return try await fetchAllNotes(request: request, context: context as any MonadServerContext)
    }

    public func fetchAllNotes(request: MonadEmpty, context: any MonadServerContext) async throws -> MonadNoteList {
        let notes = try await persistence.fetchAllNotes()
        var response = MonadNoteList()
        response.notes = notes.map { $0.toProto() }
        return response
    }
    
    public func saveNote(request: MonadNote, context: GRPCAsyncServerCallContext) async throws -> MonadNote {
        return try await saveNote(request: request, context: context as any MonadServerContext)
    }

    public func saveNote(request: MonadNote, context: any MonadServerContext) async throws -> MonadNote {
        let note = Note(from: request)
        try await persistence.saveNote(note)
        return note.toProto()
    }
    
    public func deleteNote(request: MonadDeleteNoteRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        return try await deleteNote(request: request, context: context as any MonadServerContext)
    }

    public func deleteNote(request: MonadDeleteNoteRequest, context: any MonadServerContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteNote(id: uuid)
        return MonadEmpty()
    }
}
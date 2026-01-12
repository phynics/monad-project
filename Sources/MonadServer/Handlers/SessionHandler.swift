import Foundation
import GRPC
import MonadCore
import SwiftProtobuf

final class SessionHandler: MonadSessionServiceAsyncProvider {
    private let persistence: PersistenceServiceProtocol
    
    init(persistence: PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    func fetchAllSessions(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadSessionList {
        let sessions = try await persistence.fetchAllSessions(includeArchived: true)
        var response = MonadSessionList()
        response.sessions = sessions.map { $0.toProto() }
        return response
    }
    
    func fetchSession(request: MonadFetchSessionRequest, context: GRPCAsyncServerCallContext) async throws -> MonadSession {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        
        if let session = try await persistence.fetchSession(id: uuid) {
            return session.toProto()
        } else {
            throw GRPCStatus(code: .notFound, message: "Session not found")
        }
    }
    
    func createSession(request: MonadSession, context: GRPCAsyncServerCallContext) async throws -> MonadSession {
        let session = ConversationSession(from: request)
        try await persistence.saveSession(session)
        return session.toProto()
    }
    
    func updateSession(request: MonadSession, context: GRPCAsyncServerCallContext) async throws -> MonadSession {
        return try await createSession(request: request, context: context)
    }
    
    func deleteSession(request: MonadDeleteSessionRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteSession(id: uuid)
        return MonadEmpty()
    }
    
    func archiveSession(request: MonadArchiveSessionRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        
        if var session = try await persistence.fetchSession(id: uuid) {
            session.isArchived = request.isArchived
            try await persistence.saveSession(session)
            return MonadEmpty()
        } else {
            throw GRPCStatus(code: .notFound, message: "Session not found")
        }
    }
}
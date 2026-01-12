import Foundation
import GRPC
import SwiftProtobuf

public final class SessionHandler: MonadSessionServiceAsyncProvider, Sendable {
    private let persistence: any PersistenceServiceProtocol
    
    public init(persistence: any PersistenceServiceProtocol) {
        self.persistence = persistence
    }
    
    public func fetchAllSessions(request: MonadEmpty, context: GRPCAsyncServerCallContext) async throws -> MonadSessionList {
        return try await fetchAllSessions(request: request, context: context as any MonadServerContext)
    }

    public func fetchAllSessions(request: MonadEmpty, context: any MonadServerContext) async throws -> MonadSessionList {
        let sessions = try await persistence.fetchAllSessions(includeArchived: true)
        var response = MonadSessionList()
        response.sessions = sessions.map { $0.toProto() }
        return response
    }
    
    public func fetchSession(request: MonadFetchSessionRequest, context: GRPCAsyncServerCallContext) async throws -> MonadSession {
        return try await fetchSession(request: request, context: context as any MonadServerContext)
    }

    public func fetchSession(request: MonadFetchSessionRequest, context: any MonadServerContext) async throws -> MonadSession {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        
        if let session = try await persistence.fetchSession(id: uuid) {
            return session.toProto()
        } else {
            throw GRPCStatus(code: .notFound, message: "Session not found")
        }
    }
    
    public func createSession(request: MonadSession, context: GRPCAsyncServerCallContext) async throws -> MonadSession {
        return try await createSession(request: request, context: context as any MonadServerContext)
    }

    public func createSession(request: MonadSession, context: any MonadServerContext) async throws -> MonadSession {
        let session = ConversationSession(from: request)
        try await persistence.saveSession(session)
        return session.toProto()
    }
    
    public func updateSession(request: MonadSession, context: GRPCAsyncServerCallContext) async throws -> MonadSession {
        return try await updateSession(request: request, context: context as any MonadServerContext)
    }

    public func updateSession(request: MonadSession, context: any MonadServerContext) async throws -> MonadSession {
        return try await createSession(request: request, context: context)
    }
    
    public func deleteSession(request: MonadDeleteSessionRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        return try await deleteSession(request: request, context: context as any MonadServerContext)
    }

    public func deleteSession(request: MonadDeleteSessionRequest, context: any MonadServerContext) async throws -> MonadEmpty {
        guard let uuid = UUID(uuidString: request.id) else {
            throw GRPCStatus(code: .invalidArgument, message: "Invalid UUID")
        }
        try await persistence.deleteSession(id: uuid)
        return MonadEmpty()
    }
    
    public func archiveSession(request: MonadArchiveSessionRequest, context: GRPCAsyncServerCallContext) async throws -> MonadEmpty {
        return try await archiveSession(request: request, context: context as any MonadServerContext)
    }

    public func archiveSession(request: MonadArchiveSessionRequest, context: any MonadServerContext) async throws -> MonadEmpty {
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
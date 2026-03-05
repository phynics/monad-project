@testable import MonadCore
import Foundation

public final class MockSessionPersistence: SessionPersistenceProtocol, @unchecked Sendable {
    public var sessions: [Timeline] = []

    public init() {}

    public func saveSession(_ session: Timeline) async throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    public func fetchSession(id: UUID) async throws -> Timeline? {
        return sessions.first(where: { $0.id == id })
    }

    public func fetchAllSessions(includeArchived: Bool) async throws -> [Timeline] {
        if includeArchived {
            return sessions
        } else {
            return sessions.filter { !$0.isArchived }
        }
    }

    public func deleteSession(id: UUID) async throws {
        sessions.removeAll(where: { $0.id == id })
    }
}

/// Protocol for managing conversation session lifecycle and metadata.

import Foundation

public protocol SessionPersistenceProtocol: Sendable {
    func saveSession(_ session: Timeline) async throws
    func fetchSession(id: UUID) async throws -> Timeline?
    func fetchAllSessions(includeArchived: Bool) async throws -> [Timeline]
    func deleteSession(id: UUID) async throws
}

import Foundation

public protocol SessionPersistenceProtocol: Sendable {
    func saveSession(_ session: ConversationSession) async throws
    func fetchSession(id: UUID) async throws -> ConversationSession?
    func fetchAllSessions(includeArchived: Bool) async throws -> [ConversationSession]
    func deleteSession(id: UUID) async throws
}

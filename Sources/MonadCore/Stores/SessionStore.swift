import Foundation
import Logging

public actor SessionStore {
    private let persistenceService: any SessionPersistenceProtocol
    private var loadedSessions: [UUID: Timeline] = [:]
    private let logger = Logger.module(named: "store")

    public init(persistenceService: any SessionPersistenceProtocol) async throws {
        self.persistenceService = persistenceService
        try await loadSessions()
    }

    private func loadSessions() async throws {
        let sessions = try await persistenceService.fetchAllSessions(includeArchived: false)

        for session in sessions {
            loadedSessions[session.id] = session
        }
        logger.info("Loaded \(sessions.count) active sessions into cache.")
    }

    public func getSession(id: UUID) -> Timeline? {
        return loadedSessions[id]
    }

    public func reloadSession(id: UUID) async throws {
        guard let session = try await persistenceService.fetchSession(id: id) else {
            loadedSessions.removeValue(forKey: id)
            return
        }

        loadedSessions[id] = session
    }

    public func unloadSession(id: UUID) {
        loadedSessions.removeValue(forKey: id)
    }

    /// Create a new session and store it in the database
    public func createSession(
        title: String = "New Conversation",
        workingDirectory: String? = nil,
        primaryWorkspaceId: UUID? = nil
    ) async throws -> Timeline {
        let session = Timeline(
            title: title,
            workingDirectory: workingDirectory,
            primaryWorkspaceId: primaryWorkspaceId
        )

        try await persistenceService.saveSession(session)
        loadedSessions[session.id] = session
        return session
    }

    /// Update an existing session in the database and cache
    public func updateSession(_ session: Timeline) async throws {
        try await persistenceService.saveSession(session)
        loadedSessions[session.id] = session
    }

    /// Delete a session from the database and cache
    public func deleteSession(id: UUID) async throws {
        try await persistenceService.deleteSession(id: id)
        loadedSessions.removeValue(forKey: id)
    }
}

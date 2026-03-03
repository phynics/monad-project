import Foundation
import MonadCore
import MonadShared

extension MonadClient {
    // MARK: - Prune API

    public func pruneMemories(query: String, dryRun: Bool = false) async throws -> Int {
        var request = try buildRequest(path: "/api/prune/memories", method: "POST")
        request.httpBody = try encoder.encode(PruneMemoriesRequest(query: query, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }

    public func pruneMemories(olderThanDays days: Int, dryRun: Bool = false) async throws -> Int {
        var request = try buildRequest(path: "/api/prune/memories", method: "POST")
        request.httpBody = try encoder.encode(PruneMemoriesRequest(days: days, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }

    public func pruneSessions(olderThanDays days: Int, excluding: [UUID] = [], dryRun: Bool = false)
        async throws -> Int {
        var request = try buildRequest(path: "/api/prune/sessions", method: "POST")
        request.httpBody = try encoder.encode(
            PruneSessionRequest(days: days, excludedSessionIds: excluding, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }

    public func pruneMessages(olderThanDays days: Int, dryRun: Bool = false) async throws -> Int {
        var request = try buildRequest(path: "/api/prune/messages", method: "POST")
        request.httpBody = try encoder.encode(PruneMessagesRequest(days: days, dryRun: dryRun))
        let response: PruneResponse = try await perform(request)
        return response.count
    }
}

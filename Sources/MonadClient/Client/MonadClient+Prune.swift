import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - Prune API

    func pruneMemories(query: String, dryRun: Bool = false) async throws -> Int {
        var request = try await client.buildRequest(path: "/api/prune/memories", method: "POST")
        request.httpBody = try await client.encode(PruneMemoriesRequest(query: query, dryRun: dryRun))
        let response: PruneResponse = try await client.perform(request)
        return response.count
    }

    func pruneMemories(olderThanDays days: Int, dryRun: Bool = false) async throws -> Int {
        var request = try await client.buildRequest(path: "/api/prune/memories", method: "POST")
        request.httpBody = try await client.encode(PruneMemoriesRequest(days: days, dryRun: dryRun))
        let response: PruneResponse = try await client.perform(request)
        return response.count
    }

    func pruneTimelines(olderThanDays days: Int, excluding: [UUID] = [], dryRun: Bool = false)
        async throws -> Int {
        var request = try await client.buildRequest(path: "/api/prune/sessions", method: "POST")
        request.httpBody = try await client.encode(
            PruneTimelineRequest(days: days, excludedTimelineIds: excluding, dryRun: dryRun)
        )
        let response: PruneResponse = try await client.perform(request)
        return response.count
    }

    func pruneMessages(olderThanDays days: Int, dryRun: Bool = false) async throws -> Int {
        var request = try await client.buildRequest(path: "/api/prune/messages", method: "POST")
        request.httpBody = try await client.encode(PruneMessagesRequest(days: days, dryRun: dryRun))
        let response: PruneResponse = try await client.perform(request)
        return response.count
    }
}

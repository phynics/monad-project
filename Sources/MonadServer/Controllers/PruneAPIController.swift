import Foundation
import HTTPTypes
import Hummingbird
import MonadShared
import NIOCore

public struct PruneAPIController<Context: RequestContext>: Sendable {
    public let persistenceService: PersistenceService

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/memories", use: pruneMemories)
        group.post("/sessions", use: pruneTimelines)
        group.post("/messages", use: pruneMessages)
    }

    // MARK: - Handlers

    @Sendable func pruneMemories(_ request: Request, context: Context) async throws -> PruneResponse {
        let input = try await request.decode(as: PruneMemoriesRequest.self, context: context)
        let dryRun = input.dryRun
        let count: Int

        if let query = input.query {
            count = try await persistenceService.pruneMemories(matching: query, dryRun: dryRun)
        } else if let days = input.days {
            let timeInterval = Double(days) * 24 * 60 * 60
            count = try await persistenceService.pruneMemories(
                olderThan: timeInterval, dryRun: dryRun)
        } else {
            // Default to 0 or error? Currently treating as empty op if neither provided
            count = 0
        }

        return PruneResponse(count: count, dryRun: dryRun)
    }

    @Sendable func pruneTimelines(_ request: Request, context: Context) async throws -> PruneResponse {
        let input = try await request.decode(as: PruneTimelineRequest.self, context: context)
        // Convert days to seconds
        let timeInterval = Double(input.days) * 24 * 60 * 60
        let dryRun = input.dryRun
        let count: Int
        do {
            count = try await persistenceService.pruneTimelines(
                olderThan: timeInterval, excluding: input.excludedTimelineIds, dryRun: dryRun
            )
        } catch {
            print("[PruneController] pruneTimelines error: \(error)")
            throw error
        }

        return PruneResponse(count: count, dryRun: dryRun)
    }

    @Sendable func pruneMessages(_ request: Request, context: Context) async throws -> PruneResponse {
        let input = try await request.decode(as: PruneMessagesRequest.self, context: context)
        let timeInterval = Double(input.days) * 24 * 60 * 60
        let dryRun = input.dryRun
        let count = try await persistenceService.pruneMessages(
            olderThan: timeInterval, dryRun: dryRun)

        return PruneResponse(count: count, dryRun: dryRun)
    }
}

// MARK: - DTOs
// Using shared DTOs from MonadCore

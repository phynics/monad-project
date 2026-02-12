import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import MonadClient
import NIOCore

public struct PruneController<Context: RequestContext>: Sendable {
    public let persistenceService: PersistenceService

    public init(persistenceService: PersistenceService) {
        self.persistenceService = persistenceService
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/memories", use: pruneMemories)
        group.post("/sessions", use: pruneSessions)
        group.post("/messages", use: pruneMessages)
    }

    // MARK: - Handlers

    @Sendable func pruneMemories(_ request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: PruneMemoriesRequest.self, context: context)
        let dryRun = input.dryRun ?? false
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

        let response = PruneResponse(count: count, dryRun: dryRun)
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func pruneSessions(_ request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: PruneSessionRequest.self, context: context)
        // Convert days to seconds
        let timeInterval = Double(input.days) * 24 * 60 * 60
        let dryRun = input.dryRun ?? false
        let count: Int
        do {
            count = try await persistenceService.pruneSessions(
                olderThan: timeInterval, excluding: input.excludedSessionIds ?? [], dryRun: dryRun
            )
        } catch {
            print("[PruneController] pruneSessions error: \(error)")
            throw error
        }

        let response = PruneResponse(count: count, dryRun: dryRun)
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func pruneMessages(_ request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: PruneMessagesRequest.self, context: context)
        let timeInterval = Double(input.days) * 24 * 60 * 60
        let dryRun = input.dryRun ?? false
        let count = try await persistenceService.pruneMessages(
            olderThan: timeInterval, dryRun: dryRun)

        let response = PruneResponse(count: count, dryRun: dryRun)
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

// MARK: - DTOs
// Using shared DTOs from MonadCore

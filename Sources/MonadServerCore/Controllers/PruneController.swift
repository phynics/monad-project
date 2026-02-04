import Foundation
import HTTPTypes
import Hummingbird
import MonadCore
import NIOCore

public struct PruneController<Context: RequestContext>: Sendable {
    public let persistenceService: any PersistenceServiceProtocol

    public init(persistenceService: any PersistenceServiceProtocol) {
        self.persistenceService = persistenceService
    }

    public func addRoutes(to group: RouterGroup<Context>) {
        group.post("/memories", use: pruneMemories)
        group.post("/sessions", use: pruneSessions)
        group.post("/messages", use: pruneMessages)
    }

    // MARK: - Handlers

    @Sendable func pruneMemories(_ request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: PruneQueryRequest.self, context: context)
        let count = try await persistenceService.pruneMemories(matching: input.query)

        let response = PruneResponse(count: count)
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
        let count = try await persistenceService.pruneSessions(
            olderThan: timeInterval, excluding: input.excludedSessionIds ?? [])

        let response = PruneResponse(count: count)
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    @Sendable func pruneMessages(_ request: Request, context: Context) async throws -> Response {
        let input = try await request.decode(as: PruneMessagesRequest.self, context: context)
        let timeInterval = Double(input.days) * 24 * 60 * 60
        let count = try await persistenceService.pruneMessages(olderThan: timeInterval)

        let response = PruneResponse(count: count)
        let data = try SerializationUtils.jsonEncoder.encode(response)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(
            status: .ok, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }
}

// MARK: - DTOs
// Using shared DTOs from MonadCore

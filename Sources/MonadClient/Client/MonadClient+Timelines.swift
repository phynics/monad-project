import Foundation
import MonadShared

public extension MonadChatClient {
    // MARK: - Timeline API

    /// Create a new chat timeline
    func createTimeline(
        title: String? = nil, workspaceId: UUID? = nil
    ) async throws -> Timeline {
        var request = try await client.buildRequest(path: "/api/sessions", method: "POST")
        request.httpBody = try await client.encode(
            CreateTimelineRequest(title: title, primaryWorkspaceId: workspaceId)
        )
        return try await client.perform(request)
    }

    func listTimelines() async throws -> [TimelineResponse] {
        let request = try await client.buildRequest(path: "/api/sessions", method: "GET")
        let response: PaginatedResponse<TimelineResponse> = try await client.perform(request)
        return response.items
    }

    /// Get a specific timeline by ID
    func getTimeline(id: UUID) async throws -> TimelineResponse {
        let request = try await client.buildRequest(path: "/api/sessions/\(id.uuidString)", method: "GET")
        return try await client.perform(request)
    }

    /// Update timeline title
    func updateTimelineTitle(_ title: String, timelineId: UUID) async throws {
        var request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)", method: "PATCH"
        )
        request.httpBody = try await client.encode(UpdateTimelineRequest(title: title))
        _ = try await client.performRaw(request)
    }

    /// Delete a timeline
    func deleteTimeline(_ id: UUID) async throws {
        let request = try await client.buildRequest(path: "/api/sessions/\(id.uuidString)", method: "DELETE")
        _ = try await client.performRaw(request)
    }

    /// Get timeline history
    func getHistory(timelineId: UUID) async throws -> [Message] {
        let request = try await client.buildRequest(
            path: "/api/sessions/\(timelineId.uuidString)/history", method: "GET"
        )
        let response: PaginatedResponse<Message> = try await client.perform(request)
        return response.items
    }
}

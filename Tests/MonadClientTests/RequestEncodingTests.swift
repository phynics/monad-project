import Foundation
@testable import MonadClient
import MonadCore
import MonadShared
import Testing

// MARK: - Helpers

private func makePaginatedMemories(_ items: [Memory] = []) throws -> Data {
    let response = PaginatedResponse(items: items, metadata: PaginationMetadata(page: 1, perPage: 20, totalItems: items.count))
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(response)
}

private func makePaginatedSessions(_ items: [TimelineResponse] = []) throws -> Data {
    let response = PaginatedResponse(items: items, metadata: PaginationMetadata(page: 1, perPage: 20, totalItems: items.count))
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(response)
}

@Suite struct RequestEncodingTests {
    private func makeClient() -> (MonadClient, MockSession) {
        let mockSession = MockSession()
        let config = ClientConfiguration(
            baseURL: URL(string: "http://localhost:8080")!,
            apiKey: "test-key"
        )
        let client = MonadClient(configuration: config, session: mockSession)
        return (client, mockSession)
    }

    // MARK: - Auth headers

    @Test("Requests include Authorization Bearer header when API key configured")
    func request_includesAuthorizationHeader() async throws {
        let (client, mockSession) = makeClient()
        try await mockSession.setMockData(makePaginatedMemories())
        _ = try await client.chat.listMemories()
        let req = await mockSession.lastRequest
        #expect(req?.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    }

    @Test("healthCheck does not send Authorization header")
    func healthCheck_omitsAuthorizationHeader() async throws {
        let (client, mockSession) = makeClient()
        // Default MockSession returns 200 — healthCheck should succeed without auth
        _ = try await client.healthCheck()
        let req = await mockSession.lastRequest
        #expect(req?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Requests set Content-Type to application/json")
    func request_setsContentTypeHeader() async throws {
        let (client, mockSession) = makeClient()
        try await mockSession.setMockData(makePaginatedMemories())
        _ = try await client.chat.listMemories()
        let req = await mockSession.lastRequest
        #expect(req?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    // MARK: - Sessions

    @Test("createTimeline sends POST to /api/sessions")
    func createTimeline_postToSessions() async throws {
        let (client, mockSession) = makeClient()
        let session = TimelineResponse(id: UUID(), title: "New")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try await mockSession.setMockData(encoder.encode(session))

        _ = try await client.chat.createTimeline()
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/sessions")
        #expect(req?.httpMethod == "POST")
    }

    @Test("listTimelines sends GET to /api/sessions")
    func listTimelines_getToSessions() async throws {
        let (client, mockSession) = makeClient()
        try await mockSession.setMockData(makePaginatedSessions())

        _ = try await client.chat.listTimelines()
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/sessions")
        #expect(req?.httpMethod == "GET")
    }

    @Test("getTimeline sends GET to /api/sessions/{id}")
    func getTimeline_getWithId() async throws {
        let (client, mockSession) = makeClient()
        let timelineId = UUID()
        let sessionResp = TimelineResponse(id: timelineId, title: "Test")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try await mockSession.setMockData(encoder.encode(sessionResp))

        _ = try await client.chat.getTimeline(id: timelineId)
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/sessions/\(timelineId.uuidString)")
        #expect(req?.httpMethod == "GET")
    }

    @Test("deleteTimeline sends DELETE to /api/sessions/{id}")
    func deleteTimeline_deleteWithId() async throws {
        let (client, mockSession) = makeClient()
        let timelineId = UUID()
        await mockSession.setMockData(Data())

        try await client.chat.deleteTimeline(timelineId)
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/sessions/\(timelineId.uuidString)")
        #expect(req?.httpMethod == "DELETE")
    }

    @Test("updateTimelineTitle sends PATCH to /api/sessions/{id}")
    func updateTimelineTitle_patchWithId() async throws {
        let (client, mockSession) = makeClient()
        let timelineId = UUID()
        await mockSession.setMockData(Data())

        try await client.chat.updateTimelineTitle("New Title", timelineId: timelineId)
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/sessions/\(timelineId.uuidString)")
        #expect(req?.httpMethod == "PATCH")
    }

    // MARK: - Memories

    @Test("createMemory sends POST to /api/memories with content in body")
    func createMemory_postWithBody() async throws {
        let (client, mockSession) = makeClient()
        let mem = Memory(id: UUID(), title: "T", content: "C", createdAt: Date(), updatedAt: Date())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try await mockSession.setMockData(encoder.encode(mem))

        _ = try await client.chat.createMemory(content: "Test content")
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/memories")
        #expect(req?.httpMethod == "POST")
        let body = req?.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
        #expect(body?["content"] == "Test content")
    }

    @Test("listMemories sends GET to /api/memories")
    func listMemories_getToMemories() async throws {
        let (client, mockSession) = makeClient()
        try await mockSession.setMockData(makePaginatedMemories())

        _ = try await client.chat.listMemories()
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/memories")
        #expect(req?.httpMethod == "GET")
    }

    @Test("getMemory sends GET to /api/memories/{id}")
    func getMemory_getWithId() async throws {
        let (client, mockSession) = makeClient()
        let memId = UUID()
        let mem = Memory(id: memId, title: "T", content: "C", createdAt: Date(), updatedAt: Date())
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try await mockSession.setMockData(encoder.encode(mem))

        _ = try await client.chat.getMemory(id: memId)
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/memories/\(memId.uuidString)")
        #expect(req?.httpMethod == "GET")
    }

    @Test("deleteMemory sends DELETE to /api/memories/{id}")
    func deleteMemory_deleteWithId() async throws {
        let (client, mockSession) = makeClient()
        let memId = UUID()
        await mockSession.setMockData(Data())

        try await client.chat.deleteMemory(memId)
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/memories/\(memId.uuidString)")
        #expect(req?.httpMethod == "DELETE")
    }

    // MARK: - System

    @Test("clearConfiguration sends DELETE to /api/config")
    func clearConfiguration_deleteToConfig() async throws {
        let (client, mockSession) = makeClient()
        await mockSession.setMockData(Data())

        try await client.clearConfiguration()
        let req = await mockSession.lastRequest
        #expect(req?.url?.path == "/api/config")
        #expect(req?.httpMethod == "DELETE")
    }

    // MARK: - Error handling

    @Test("401 response throws unauthorized error")
    func response_401_throwsUnauthorized() async throws {
        let (client, mockSession) = makeClient()
        let url = try #require(URL(string: "http://localhost"))
        let resp = try #require(HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil))
        await mockSession.setMockResponse(resp)
        do {
            _ = try await client.chat.listMemories()
            Issue.record("Expected unauthorized error")
        } catch MonadClientError.unauthorized { /* expected */ }
        catch { Issue.record("Expected unauthorized, got \(error)") }
    }

    @Test("404 response throws notFound error")
    func response_404_throwsNotFound() async throws {
        let (client, mockSession) = makeClient()
        let url = try #require(URL(string: "http://localhost"))
        let resp = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
        await mockSession.setMockResponse(resp)
        do {
            _ = try await client.chat.listMemories()
            Issue.record("Expected notFound error")
        } catch MonadClientError.notFound { /* expected */ }
        catch { Issue.record("Expected notFound, got \(error)") }
    }

    @Test("500 response throws httpError with status code")
    func response_500_throwsHttpError() async throws {
        let (client, mockSession) = makeClient()
        let url = try #require(URL(string: "http://localhost"))
        let resp = try #require(HTTPURLResponse(url: url, statusCode: 500, httpVersion: nil, headerFields: nil))
        await mockSession.setMockResponse(resp)
        do {
            _ = try await client.chat.listMemories()
            Issue.record("Expected error to be thrown")
        } catch let error as MonadClientError {
            if case let .httpError(code, _) = error {
                #expect(code == 500)
            } else {
                Issue.record("Expected httpError, got \(error)")
            }
        }
    }

    @Test("Network error is wrapped in MonadClientError.networkError")
    func networkError_isWrapped() async throws {
        let (client, mockSession) = makeClient()
        struct NetError: Error {}
        await mockSession.setMockError(NetError())

        do {
            _ = try await client.chat.listMemories()
            Issue.record("Expected error to be thrown")
        } catch let error as MonadClientError {
            if case .networkError = error { /* expected */ }
            else { Issue.record("Expected networkError, got \(error)") }
        }
    }
}

import Foundation
@testable import MonadClient
@testable import MonadShared
import Testing

public actor MockSession: URLSessionProtocol {
    public var lastRequest: URLRequest?
    public var mockData: Data?
    public var mockResponse: URLResponse?
    public var mockError: Error?

    public init() {}

    public func setMockData(_ data: Data?) {
        mockData = data
    }

    public func setMockResponse(_ response: URLResponse) {
        mockResponse = response
    }

    public func setMockError(_ error: Error) {
        mockError = error
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastRequest = request
        if let error = mockError {
            throw error
        }
        let data = mockData ?? Data()
        let response =
            mockResponse
                ?? HTTPURLResponse(
                    url: request.url ?? URL(string: "http://localhost")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
        return (data, response)
    }

    public func bytes(for _: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        fatalError("Not implemented for generic mock")
    }
}

@Suite struct MonadClientErgonomicsTests {
    @Test("Test Client Route Mappings for recent extensions")
    func clientErgonomics() async throws {
        let mockSession = MockSession()
        let config = try ClientConfiguration(
            baseURL: #require(URL(string: "http://localhost:8080")),
            apiKey: "test-key"
        )

        let client = MonadClient(configuration: config, session: mockSession)

        // 1. Memory Test
        let memoryId = UUID()
        let mockMemory = Memory(id: memoryId, title: "Mock", content: "Test", createdAt: Date(), updatedAt: Date())
        let memEncoder = JSONEncoder()
        memEncoder.dateEncodingStrategy = .iso8601
        await mockSession.setMockData(try memEncoder.encode(mockMemory))

        _ = try await client.chat.getMemory(id: memoryId)
        var lastReq = await mockSession.lastRequest
        #expect(lastReq?.url?.path == "/api/memories/\(memoryId.uuidString)")
        #expect(lastReq?.httpMethod == "GET")

        // 2. AgentTemplates Test
        try await mockSession.setMockData(JSONEncoder().encode([] as [AgentTemplate]))
        _ = try await client.chat.listAgentTemplates()
        lastReq = await mockSession.lastRequest
        #expect(lastReq?.url?.path == "/api/agentTemplates")
        #expect(lastReq?.httpMethod == "GET")

        // 3. System Configuration Clear Test
        await mockSession.setMockData(Data())
        try await client.clearConfiguration()
        lastReq = await mockSession.lastRequest
        #expect(lastReq?.url?.path == "/api/config")
        #expect(lastReq?.httpMethod == "DELETE")
    }
}

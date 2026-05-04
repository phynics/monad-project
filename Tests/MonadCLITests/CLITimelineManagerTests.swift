import Foundation
@testable import MonadCLI
import ArgumentParser
import MonadClient
import MonadShared
import Testing

private actor CLIMockSession: URLSessionProtocol {
    struct Response {
        let data: Data
        let response: URLResponse
    }

    private var responses: [String: Response] = [:]

    func setResponse(path: String, statusCode: Int, body: Data = Data()) {
        let url = URL(string: "http://localhost:8080\(path)")!
        responses[path] = Response(
            data: body,
            response: HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        if let response = responses[path] {
            return (response.data, response.response)
        }

        let url = request.url ?? URL(string: "http://localhost:8080")!
        return (
            Data(),
            HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
        )
    }

    func bytes(for _: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        fatalError("Not implemented for CLI tests")
    }
}

@Suite struct CLITimelineManagerTests {
    @Test("explicit missing timeline fails instead of resuming from empty history")
    func resolveTimeline_explicitMissingTimelineThrows() async throws {
        let timelineId = UUID()
        let session = CLIMockSession()
        await session.setResponse(path: "/api/sessions/\(timelineId.uuidString)", statusCode: 404)
        await session.setResponse(path: "/api/sessions/\(timelineId.uuidString)/history", statusCode: 200, body: try JSONEncoder().encode(PaginatedResponse<Message>(items: [], metadata: PaginationMetadata(page: 1, perPage: 50, totalItems: 0))))

        let config = ClientConfiguration(baseURL: try #require(URL(string: "http://localhost:8080")), apiKey: "test-key")
        let client = MonadClient(configuration: config, session: session)
        let manager = CLITimelineManager(client: client)

        await #expect(throws: ExitCode.self) {
            _ = try await manager.resolveTimeline(
                explicitId: timelineId.uuidString,
                localConfig: LocalConfig()
            )
        }
    }
}

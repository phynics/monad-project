import Foundation
import MonadShared

/// HTTP client for communicating with MonadServer
public actor MonadClient {
    let configuration: ClientConfiguration
    let session: any URLSessionProtocol
    let decoder: JSONDecoder
    let encoder: JSONEncoder
    let sseReader: SSEStreamReader

    public init(configuration: ClientConfiguration = .fromEnvironment(), session: (any URLSessionProtocol)? = nil) {
        self.configuration = configuration

        if let session = session {
            self.session = session
        } else {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = configuration.timeout
            self.session = URLSession(configuration: sessionConfig)
        }

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        sseReader = SSEStreamReader()
    }

    public nonisolated var chat: MonadChatClient { MonadChatClient(client: self) }
    public nonisolated var workspace: MonadWorkspaceClient { MonadWorkspaceClient(client: self) }

    // MARK: - Internal Helpers for Extracted Clients

    public func buildRequest(path: String, method: String, requiresAuth: Bool = true) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.baseURL) else {
            throw MonadClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if requiresAuth, let apiKey = configuration.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    public func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    public func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await performRaw(request)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MonadClientError.decodingError(error)
        }
    }

    public func performRaw(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            configuration.logger.error("Network error: \(error.localizedDescription)")
            throw MonadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MonadClientError.unknown("Invalid response type")
        }

        let url = request.url?.path ?? "unknown"

        switch httpResponse.statusCode {
        case 200 ... 299:
            return (data, response)
        case 401:
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            configuration.logger.error("HTTP 401 Unauthorized for \(url): \(body)")
            throw MonadClientError.unauthorized
        case 404:
            configuration.logger.warning("HTTP 404 Not Found for \(url)")
            throw MonadClientError.notFound
        default:
            let message = String(data: data, encoding: .utf8)
            configuration.logger.error(
                "HTTP \(httpResponse.statusCode) for \(url): \(message ?? "no body")"
            )
            throw MonadClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }
    }
    
    public func fetchStreamBytes(request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        return try await session.bytes(for: request)
    }
}

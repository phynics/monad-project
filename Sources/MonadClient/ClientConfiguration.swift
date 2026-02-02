import Foundation

/// Configuration for connecting to MonadServer
public struct ClientConfiguration: Sendable {
    /// Base URL of the MonadServer
    public let baseURL: URL

    /// API key for authentication
    public let apiKey: String?

    /// Request timeout in seconds
    public let timeout: TimeInterval

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        apiKey: String? = nil,
        timeout: TimeInterval = 60
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
    }

    /// Create configuration from environment variables
    public static func fromEnvironment() -> ClientConfiguration {
        let baseURLString =
            ProcessInfo.processInfo.environment["MONAD_SERVER_URL"] ?? "http://127.0.0.1:8080"
        let apiKey = ProcessInfo.processInfo.environment["MONAD_API_KEY"]
        let timeout =
            TimeInterval(ProcessInfo.processInfo.environment["MONAD_TIMEOUT"] ?? "60") ?? 60

        return ClientConfiguration(
            baseURL: URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:8080")!,
            apiKey: apiKey,
            timeout: timeout
        )
    }
}

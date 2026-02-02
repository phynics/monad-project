import Foundation
import Logging

/// Configuration for connecting to MonadServer
public struct ClientConfiguration: Sendable {
    /// Base URL of the MonadServer
    public let baseURL: URL

    /// API key for authentication
    public let apiKey: String?

    /// Request timeout in seconds
    public let timeout: TimeInterval

    /// Enable verbose debug logging
    public let verbose: Bool

    /// Logger instance
    public let logger: Logger

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:8080")!,
        apiKey: String? = nil,
        timeout: TimeInterval = 60,
        verbose: Bool = false
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeout = timeout
        self.verbose = verbose

        var logger = Logger(label: Bundle.main.bundleIdentifier ?? "com.monad.client")
        logger.logLevel = verbose ? .debug : .info
        self.logger = logger
    }

    /// Create configuration from environment variables
    public static func fromEnvironment() -> ClientConfiguration {
        let baseURLString =
            ProcessInfo.processInfo.environment["MONAD_SERVER_URL"] ?? "http://127.0.0.1:8080"
        let apiKey = ProcessInfo.processInfo.environment["MONAD_API_KEY"]
        let timeout =
            TimeInterval(ProcessInfo.processInfo.environment["MONAD_TIMEOUT"] ?? "60") ?? 60

        let verbose =
            ProcessInfo.processInfo.environment["MONAD_VERBOSE"] == "1"
            || ProcessInfo.processInfo.environment["MONAD_VERBOSE"] == "true"

        return ClientConfiguration(
            baseURL: URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:8080")!,
            apiKey: apiKey,
            timeout: timeout,
            verbose: verbose
        )
    }
}

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

    /// Attempt to create a configuration by discovering a server on the network.
    /// If an explicit URL is provided (or in env), it is used.
    /// Otherwise, scans for Bonjour services.
    /// - Parameters:
    ///   - explicitURL: A URL provided by argument or UI.
    ///   - apiKey: API Key to use.
    ///   - verbose: Verbose logging.
    ///   - timeout: How long to wait for discovery before falling back to default.
    public static func autoDetect(
        explicitURL: URL? = nil,
        apiKey: String? = nil,
        verbose: Bool = false,
        timeout: TimeInterval = 2.0
    ) async -> ClientConfiguration {
        // 1. Explicit URL
        if let url = explicitURL {
            return ClientConfiguration(baseURL: url, apiKey: apiKey, verbose: verbose)
        }

        // 2. Environment
        if let envURLString = ProcessInfo.processInfo.environment["MONAD_SERVER_URL"],
            let envURL = URL(string: envURLString)
        {
            return ClientConfiguration(baseURL: envURL, apiKey: apiKey, verbose: verbose)
        }

        let logger = Logger(label: "com.monad.client.discovery")

        // 3. Discovery
        logger.info("No server URL configured. Searching for Monad Server on local network...")

        let discovery = ServerDiscovery(logger: logger)
        let stream = discovery.startDiscovery()

        let discoveredURL: URL? = await withTaskGroup(of: URL?.self) { group in
            group.addTask {
                for await url in stream {
                    return url
                }
                return nil
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }

            // Wait for the first task to complete (either found URL or timeout)
            let result = await group.next()
            // Cancel pending tasks (stops discovery or timer)
            group.cancelAll()
            return result ?? nil
        }

        discovery.stop()

        if let url = discoveredURL {
            logger.info("Discovered server at \(url). Using this endpoint.")
            return ClientConfiguration(baseURL: url, apiKey: apiKey, verbose: verbose)
        }

        logger.info("No server found via discovery. Using default localhost.")
        // Fallback to default
        return ClientConfiguration(apiKey: apiKey, verbose: verbose)
    }
}

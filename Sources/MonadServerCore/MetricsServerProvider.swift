import Foundation
import MonadCore
import Logging

/// A ServiceProvider that manages the Prometheus metrics server.
public final class MetricsServerProvider: ServiceProvider, @unchecked Sendable {
    public let name = "Metrics Server"
    private let logger = Logger(label: "com.monad.server.metrics-provider")
    
    private let metrics: ServerMetrics
    private let port: Int
    
    public init(metrics: ServerMetrics, port: Int = 8080) {
        self.metrics = metrics
        self.port = port
    }
    
    public func start() async throws {
        logger.info("Starting Metrics server on port \(port)...")
        // Start in a background task as it blocks or runs an event loop
        Task {
            do {
                try await metrics.startMetricsServer(port: port)
            } catch {
                logger.error("Metrics server failed: \(error)")
            }
        }
    }
    
    public func shutdown() async throws {
        logger.info("Metrics server shutting down (lifecycle managed by ServerMetrics).")
        // ServerMetrics might need a shutdown method if it has one
    }
}

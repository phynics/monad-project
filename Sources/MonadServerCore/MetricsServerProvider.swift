import Foundation
import MonadCore
import Logging

/// A `ServiceProvider` that manages the Prometheus metrics server.
///
/// This provider is responsible for exporting application-level telemetry
/// data gathered via `ServerMetrics`.
public final class MetricsServerProvider: ServiceProvider, @unchecked Sendable {
    /// human-readable identifier.
    public let name = "Metrics Server"
    private let logger = Logger(label: "com.monad.server.metrics-provider")
    
    private let metrics: ServerMetrics
    private let port: Int
    
    /// Initializes the metrics server provider.
    /// - Parameters:
    ///   - metrics: The metrics management utility to export.
    ///   - port: The port for Prometheus to scrape (defaults to 8080).
    public init(metrics: ServerMetrics, port: Int = 8080) {
        self.metrics = metrics
        self.port = port
    }
    
    /// Starts the Prometheus metrics server in a background task.
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
    
    /// Stub for graceful shutdown.
    /// - Note: Lifecycle is currently managed by the internal Prometheus library components.
    public func shutdown() async throws {
        logger.info("Metrics server shutting down (lifecycle managed by ServerMetrics).")
    }
}
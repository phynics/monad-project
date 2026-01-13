import Foundation
import MonadCore
import Logging

/// A protocol that defines the common interface for all server-side service providers.
///
/// Adheres to the **Interface Segregation Principle (ISP)** by defining only the 
/// necessary methods for lifecycle management that the orchestrator needs.
public protocol ServiceProvider: Sendable {
    /// The human-readable name of the provider, used for logging and diagnostics.
    var name: String { get }
    
    /// Bootstraps the service and its internal resources.
    /// - Throws: If the service fails to start (e.g., port binding failure).
    func start() async throws
    
    /// Gracefully shuts down the service and releases all resources.
    func shutdown() async throws
}

/// The central orchestrator responsible for managing the lifecycle and dependency
/// injection of all server-side services.
///
/// Adheres to **SOLID** and **CLEAN** principles:
/// - **Single Responsibility Principle (SRP)**: Coordinates the startup/shutdown sequence of disparate services.
/// - **Open/Closed Principle (OCP)**: New services can be added by implementing the `ServiceProvider` protocol without modifying the orchestrator's core logic.
/// - **Dependency Inversion Principle (DIP)**: Depends on the `ServiceProvider` abstraction rather than concrete server implementations.
public final class ServiceProviderOrchestrator: Sendable {
    private let logger = Logger(label: "com.monad.server.orchestrator")
    
    /// Centralized handler for mapping domain errors to gRPC statuses and recording telemetry.
    public let errorHandler: ServerErrorHandler
    
    /// Management utility for Prometheus metrics and observability.
    public let metrics: ServerMetrics
    
    /// Persistence layer for database access.
    public let persistence: any PersistenceServiceProtocol
    
    /// Large Language Model service for AI processing.
    public let llm: any LLMServiceProtocol
    
    private let providers: [any ServiceProvider]
    
    /// Initializes the orchestrator with its core dependencies.
    /// - Parameters:
    ///   - persistence: The persistence service implementation.
    ///   - llm: The LLM service implementation.
    ///   - errorHandler: Optional custom error handler.
    ///   - metrics: Optional custom metrics manager.
    ///   - additionalProviders: An array of optional service providers (e.g., gRPC server, background workers).
    public init(
        persistence: any PersistenceServiceProtocol,
        llm: any LLMServiceProtocol,
        errorHandler: ServerErrorHandler = ServerErrorHandler(),
        metrics: ServerMetrics = ServerMetrics(),
        additionalProviders: [any ServiceProvider] = []
    ) {
        self.persistence = persistence
        self.llm = llm
        self.errorHandler = errorHandler
        self.metrics = metrics
        self.providers = additionalProviders
    }
    
    /// Bootstraps all managed services in the correct dependency order.
    ///
    /// The sequence follows a strict priority:
    /// 1. Metrics (to ensure subsequent steps are recorded)
    /// 2. LLM Configuration
    /// 3. All registered `ServiceProvider` implementations
    public func startup() async throws {
        logger.info("Orchestrator: Starting services...")
        
        // 1. Metrics bootstrap
        metrics.bootstrap()
        
        // 2. LLM configuration
        await llm.loadConfiguration()
        
        // 3. Start additional providers
        for provider in providers {
            logger.info("Orchestrator: Starting provider: \(provider.name)")
            try await provider.start()
        }
        
        logger.info("Orchestrator: All services active.")
    }
    
    /// Gracefully shuts down all managed services in reverse dependency order.
    public func shutdown() async throws {
        logger.info("Orchestrator: Shutting down services...")
        
        for provider in providers.reversed() {
            logger.info("Orchestrator: Stopping provider: \(provider.name)")
            try await provider.shutdown()
        }
        
        logger.info("Orchestrator: Shutdown complete.")
    }
}
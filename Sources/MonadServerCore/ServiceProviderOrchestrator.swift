import Foundation
import MonadCore
import Logging

/// A protocol that defines the common interface for all server-side service providers.
/// Adheres to the Interface Segregation Principle.
public protocol ServiceProvider: Sendable {
    var name: String { get }
    func start() async throws
    func shutdown() async throws
}

/// The central orchestrator responsible for managing the lifecycle and dependency
/// injection of all server-side services. Adheres to SOLID and CLEAN principles
/// by providing a single point of coordination for modular components.
public final class ServiceProviderOrchestrator: Sendable {
    private let logger = Logger(label: "com.monad.server.orchestrator")
    
    // Core Infrastructure
    public let errorHandler: ServerErrorHandler
    public let metrics: ServerMetrics
    
    // Domain Services
    public let persistence: any PersistenceServiceProtocol
    public let llm: any LLMServiceProtocol
    
    private let providers: [any ServiceProvider]
    
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
    public func startup() async throws {
        logger.info("Orchestrator: Starting services...")
        
        // 1. Metrics bootstrap
        metrics.bootstrap()
        
        // 2. LLM configuration
        try await llm.loadConfiguration()
        
        // 3. Start additional providers
        for provider in providers {
            logger.info("Orchestrator: Starting provider: \(provider.name)")
            try await provider.start()
        }
        
        logger.info("Orchestrator: All services active.")
    }
    
    /// Gracefully shuts down all managed services.
    public func shutdown() async throws {
        logger.info("Orchestrator: Shutting down services...")
        
        for provider in providers.reversed() {
            logger.info("Orchestrator: Stopping provider: \(provider.name)")
            try await provider.shutdown()
        }
        
        logger.info("Orchestrator: Shutdown complete.")
    }
}

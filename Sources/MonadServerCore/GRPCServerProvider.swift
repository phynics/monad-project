import Foundation
import GRPC
import NIOPosix
import NIOCore
import MonadCore
import Logging

/// A `ServiceProvider` that manages the lifecycle of the gRPC server and its handlers.
///
/// This provider encapsulates the **NIO** and **gRPC-Swift** boilerplace, allowing
/// the orchestrator to manage it as a high-level component.
public final class GRPCServerProvider: ServiceProvider, @unchecked Sendable {
    /// human-readable identifier.
    public let name = "gRPC Server"
    private let logger = Logger(label: "com.monad.server.grpc")
    
    private let host: String
    private let port: Int
    private let handlers: [any CallHandlerProvider]
    
    private var server: GRPC.Server?
    private let group: EventLoopGroup
    
    /// Initializes the gRPC server provider.
    /// - Parameters:
    ///   - host: IP address to bind to (defaults to all interfaces).
    ///   - port: Port to listen on (defaults to 50051).
    ///   - handlers: An array of gRPC service handlers (e.g., `ChatHandler`).
    ///   - numberOfThreads: Number of threads for the event loop group.
    public init(
        host: String = "0.0.0.0",
        port: Int = 50051,
        handlers: [any CallHandlerProvider],
        numberOfThreads: Int = System.coreCount
    ) {
        self.host = host
        self.port = port
        self.handlers = handlers
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }
    
    /// Binds and starts the insecure gRPC server.
    public func start() async throws {
        logger.info("Starting gRPC server on \(host):\(port)...")
        
        let server = try await Server.insecure(group: group)
            .withServiceProviders(handlers)
            .bind(host: host, port: port)
            .get()
        
        self.server = server
        logger.info("gRPC server active on \(server.channel.localAddress!)")
    }
    
    /// Gracefully stops the server and shuts down the NIO event loop group.
    public func shutdown() async throws {
        logger.info("Shutting down gRPC server...")
        try await server?.close().get()
        try await group.shutdownGracefully()
        logger.info("gRPC server stopped.")
    }
    
    /// Returns a future that completes when the server closes.
    /// Used for blocking the main thread until exit.
    public var onClose: EventLoopFuture<Void>? {
        server?.onClose
    }
}
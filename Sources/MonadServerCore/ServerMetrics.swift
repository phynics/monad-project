import Foundation
import Metrics
import Prometheus
import NIOHTTP1
import NIOCore
import NIOPosix

/// Manages server-side metrics and observability using SwiftPrometheus.
/// Adheres to CLEAN principles by providing a simple, unified interface
/// for metrics collection and exportation.
public final class ServerMetrics: Sendable {
    public let registry = PrometheusCollectorRegistry()
    private let factory: PrometheusMetricsFactory
    
    public init() {
        self.factory = PrometheusMetricsFactory(registry: registry)
    }
    
    /// Bootstraps the global MetricsSystem with the Prometheus backend.
    /// Should be called once during server startup.
    public func bootstrap() {
        MetricsSystem.bootstrap(factory)
    }
    
    /// Generates the Prometheus-formatted metrics string for scraping.
    public func export() -> String {
        var buffer = [UInt8]()
        registry.emit(into: &buffer)
        return String(decoding: buffer, as: UTF8.self)
    }
    
    /// Starts a minimal HTTP server to expose the /metrics endpoint.
    /// - Parameter port: The port to listen on (default 8080).
    public func startMetricsServer(port: Int = 8080) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let handler = MetricsHttpHandler(metrics: self)
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(handler)
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        let channel = try await bootstrap.bind(host: "0.0.0.0", port: port).get()
        print("Metrics server started on port \(port) at /metrics")
        
        // Ensure the server closes when the process terminates
        try await channel.closeFuture.get()
    }
}

/// A simple NIO handler to serve Prometheus metrics over HTTP.
private final class MetricsHttpHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private let metrics: ServerMetrics
    
    init(metrics: ServerMetrics) {
        self.metrics = metrics
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        
        guard case .head(let request) = part else { return }
        
        if request.uri == "/metrics" {
            let body = metrics.export()
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/plain; version=0.0.4")
            headers.add(name: "Content-Length", value: "\(body.utf8.count)")
            
            let responseHead = HTTPResponseHead(version: request.version, status: .ok, headers: headers)
            context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
            
            var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
            buffer.writeString(body)
            context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        } else {
            let responseHead = HTTPResponseHead(version: request.version, status: .notFound)
            context.write(self.wrapOutboundOut(.head(responseHead)), promise: nil)
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

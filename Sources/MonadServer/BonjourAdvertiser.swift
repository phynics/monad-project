import Foundation
import Logging
import ServiceLifecycle

/// Advertises the Monad Server on the local network using Bonjour (ZeroConf).
final class BonjourAdvertiser: NSObject, NetServiceDelegate, Service, @unchecked Sendable {
    private let service: NetService
    private let logger: Logger

    init(
        port: Int, name: String = "Monad Server",
        logger: Logger = Logger(label: "com.monad.server.bonjour")
    ) {
        self.service = NetService(
            domain: "local.", type: "_monad-server._tcp.", name: name, port: Int32(port))
        self.logger = logger
        super.init()
        self.service.delegate = self
    }

    func run() async throws {
        // NetService requires a RunLoop. We schedule it on the main run loop.
        await MainActor.run {
            logger.info(
                "Starting Bonjour advertisement for service type '_monad-server._tcp.' on port \(service.port)"
            )
            service.schedule(in: .main, forMode: .common)
            service.publish()
        }
        
        // Use cancelWhenGracefulShutdown to properly respond to shutdown signals
        try? await cancelWhenGracefulShutdown {
            // Wait for cancellation
            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        
        // Clean up on cancellation
        await MainActor.run {
            service.stop()
        }
        logger.info("Bonjour service stopped")
    }

    // MARK: - NetServiceDelegate

    func netServiceDidPublish(_ sender: NetService) {
        logger.info(
            "Bonjour service published successfully: \(sender.name).\(sender.type)\(sender.domain)")
    }

    func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        logger.error("Failed to publish Bonjour service via NetService. Errors: \(errorDict)")
    }

    func netServiceDidStop(_ sender: NetService) {
        logger.info("Bonjour service stopped")
    }
}

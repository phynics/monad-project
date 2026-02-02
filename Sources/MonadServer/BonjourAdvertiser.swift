import Foundation
import Logging

/// Advertises the Monad Server on the local network using Bonjour (ZeroConf).
final class BonjourAdvertiser: NSObject, NetServiceDelegate, @unchecked Sendable {
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

    func start() {
        // NetService requires a RunLoop. We schedule it on the main run loop.
        DispatchQueue.main.async {
            self.logger.info(
                "Starting Bonjour advertisement for service type '_monad-server._tcp.' on port \(self.service.port)"
            )
            self.service.schedule(in: .main, forMode: .common)
            self.service.publish()
        }
    }

    func stop() {
        DispatchQueue.main.async {
            self.service.stop()
        }
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

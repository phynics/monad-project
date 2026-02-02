import Foundation
import Logging

/// Discovers Monad Servers on the local network using Bonjour (NetServiceBrowser).
public final class ServerDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate,
    @unchecked Sendable
{
    private let browser = NetServiceBrowser()
    private var discoveredServices: [NetService] = []
    private let logger: Logger
    private var onFound: ((URL) -> Void)?

    // We use a dedicated thread for the RunLoop requirement of NetServiceBrowser
    private let discoveryThread: Thread

    // To protect discoveredServices access
    private let queue = DispatchQueue(label: "com.monad.client.discovery.state")

    public init(logger: Logger = Logger(label: "com.monad.client.discovery")) {
        self.logger = logger

        self.discoveryThread = Thread {
            // Keep the run loop alive
            RunLoop.current.add(NSMachPort(), forMode: .default)
            RunLoop.current.run()
        }
        self.discoveryThread.name = "com.monad.client.discovery"
        self.discoveryThread.start()

        super.init()
        self.browser.delegate = self
    }

    /// Starts discovery and returns a stream of found server URLs.
    /// - Returns: An AsyncStream that yields URLs (e.g. "http://machine.local:8080")
    public func startDiscovery() -> AsyncStream<URL> {
        return AsyncStream { continuation in
            self.onFound = { url in
                continuation.yield(url)
            }

            self.perform {
                self.browser.schedule(in: RunLoop.current, forMode: .default)
                self.browser.searchForServices(ofType: "_monad-server._tcp", inDomain: "local.")
                self.logger.info("Started Bonjour discovery for _monad-server._tcp")
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stop()
            }
        }
    }

    public func stop() {
        self.perform {
            self.browser.stop()
        }
        self.queue.sync {
            self.discoveredServices.removeAll()
        }
    }

    // Helper to run block on the discovery thread
    private func perform(_ block: @escaping @Sendable () -> Void) {
        // We can use perform(_:on:with:waitUntilDone:) but explicit bridging is tricky in pure swift sometimes.
        // Easier: NSObject.perform
        self.perform(
            #selector(runBlock(_:)), on: self.discoveryThread, with: BlockWrapper(block),
            waitUntilDone: false)
    }

    @objc private func runBlock(_ wrapper: BlockWrapper) {
        wrapper.block()
    }

    // MARK: - NetServiceBrowserDelegate

    public func netServiceBrowser(
        _ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool
    ) {
        logger.debug("Found service: \(service.name)")

        // We must retain the service to resolve it
        self.queue.sync {
            self.discoveredServices.append(service)
        }

        service.delegate = self
        // Resolve on the same runloop
        service.schedule(in: RunLoop.current, forMode: .default)
        service.resolve(withTimeout: 5.0)
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool
    ) {
        logger.debug("Service removed: \(service.name)")
        // Logic to remove from list if needed, but for discovery stream we might just ignore removals or need a more complex state.
        // For 'Auto-Discovery' we typically just want "Give me one that works".
    }

    // MARK: - NetServiceDelegate

    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let port = sender.port

        if port == -1 { return }

        let urlString = "http://\(host):\(port)"
        if let url = URL(string: urlString) {
            logger.info("Resolved server service to: \(url)")
            self.onFound?(url)
        }
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        logger.error("Failed to resolve service \(sender.name): \(errorDict)")
    }
}

// Wrapper Helper
private final class BlockWrapper: NSObject {
    let block: () -> Void
    init(_ block: @escaping () -> Void) {
        self.block = block
    }
}

import PKShared
import MonadShared
import ArgumentParser
import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import PositronicKit
import ServiceLifecycle
import UnixSignals

@available(macOS 14.0, *)
public struct Server: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "server",
        abstract: "Monad AI Assistant Server",
        discussion: """
        A REST API server for the Monad AI Assistant.

        EXAMPLES:
          monad server                          Start on default port 8080
          monad server --port 3000              Start on port 3000
          monad server -h 0.0.0.0 -p 8080       Bind to all interfaces
          monad server --verbose                Enable verbose logging

        API ENDPOINTS:
          GET  /health                          Health check
          GET  /api/sessions                    List sessions
          POST /api/sessions                    Create session
          POST /api/sessions/:id/chat/stream    Chat with streaming
          GET  /api/memories                    List memories
          GET  /api/notes                       List notes
          GET  /api/tools                       List tools
          GET  /api/config                      Get LLM configuration

        AUTHENTICATION:
          All /api/* endpoints require an API key via Authorization header.
        """,
        version: "1.0.0",
        helpNames: [.short, .long]
    )

    @Option(name: .shortAndLong, help: "Hostname to bind to")
    public var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong, help: "Port to listen on")
    public var port: Int = 8080

    @Flag(name: .long, help: "Enable verbose debug logging")
    public var verbose: Bool = false

    public init() {}

    public func run() async throws {
        // Initialize Logging
        LoggingSystem.bootstrap { label in
            var handler = PKLogHandler(label: label)
            handler.logLevel = verbose ? .debug : .info
            return handler
        }

        let logger = Logger.module(named: "server")

        let context = try await MonadServerFactory.createServerContext(
            hostname: hostname,
            port: port,
            verbose: verbose,
            logger: logger
        )

        try await context.serviceGroup.run()
    }
}

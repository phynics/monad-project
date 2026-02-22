import MonadShared
import ArgumentParser
import Foundation
import Hummingbird
import Logging
import MonadCore
import ServiceLifecycle
import UnixSignals
import HummingbirdWebSocket
import Dependencies

@main
@available(macOS 14.0, *)
struct MonadServer: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "monad-server",
        abstract: "Monad AI Assistant Server",
        discussion: """
            A REST API server for the Monad AI Assistant.

            EXAMPLES:
              monad-server                          Start on default port 8080
              monad-server --port 3000              Start on port 3000
              monad-server -h 0.0.0.0 -p 8080       Bind to all interfaces
              monad-server --verbose                Enable verbose logging

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

    typealias AppRequestContext = BasicWebSocketRequestContext
    
    @Option(name: .shortAndLong, help: "Hostname to bind to")
    var hostname: String = "127.0.0.1"

    @Option(name: .shortAndLong, help: "Port to listen on")
    var port: Int = 8080

    @Flag(name: .long, help: "Enable verbose debug logging")
    var verbose: Bool = false

    func run() async throws {
        let logger = Logger.server
        
        let context = try await MonadServerFactory.createServerContext(
            hostname: hostname,
            port: port,
            verbose: verbose,
            logger: logger
        )

        try await withDependencies {
            $0 = context.dependencies
        } operation: {
            try await context.serviceGroup.run()
        }
    }
}

import Foundation
import OSLog

/// Error types for MCP Transport
public enum MCPTransportError: LocalizedError, Sendable {
    case connectionFailed(String)
    case readError(String)
    case writeError(String)
    case closed

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .readError(let reason): return "Read error: \(reason)"
        case .writeError(let reason): return "Write error: \(reason)"
        case .closed: return "Connection closed"
        }
    }
}

/// Protocol defining transport for MCP JSON-RPC messages
public protocol MCPTransport: Sendable {
    /// Start the transport connection
    func start() async throws

    /// Send a message (JSON-RPC request/notification)
    func send(_ data: Data) async throws

    /// Stream of incoming messages
    var messages: AsyncStream<Data> { get }

    /// Close the transport
    func close() async
}

/// Transport implementation using Standard Input/Output (stdio)
/// Used for communicating with local MCP servers running as subprocesses
#if os(macOS)
    public actor StdioTransport: MCPTransport {
        public let command: String
        public let arguments: [String]
        public let environment: [String: String]

        private var process: Process?
        private var stdinPipe: Pipe?
        private var stdoutPipe: Pipe?
        private var stderrPipe: Pipe?

        private let logger = Logger(subsystem: "com.monad.assistant", category: "mcp-transport")

        private var continuation: AsyncStream<Data>.Continuation?
        nonisolated public let messages: AsyncStream<Data>

        public init(command: String, arguments: [String] = [], environment: [String: String] = [:])
        {
            self.command = command
            self.arguments = arguments
            self.environment = environment

            var continuation: AsyncStream<Data>.Continuation!
            self.messages = AsyncStream { cont in
                continuation = cont
            }
            self.continuation = continuation
        }

        public func start() async throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments

            // Merge environment
            var env = ProcessInfo.processInfo.environment
            env.merge(environment) { (_, new) in new }
            process.environment = env

            let stdin = Pipe()
            let stdout = Pipe()
            let stderr = Pipe()

            process.standardInput = stdin
            process.standardOutput = stdout
            process.standardError = stderr

            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.stderrPipe = stderr
            self.process = process

            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }

                Task {
                    await self?.emit(data: data)
                }
            }

            stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let log = String(data: data, encoding: .utf8) else { return }
                Task {
                    await self?.logStderr(log)
                }
            }

            process.terminationHandler = { [weak self] _ in
                Task {
                    await self?.handleTermination()
                }
            }

            do {
                try process.run()
                logger.info("MCP Server started: \(self.command)")
            } catch {
                logger.error("Failed to start MCP Server: \(error.localizedDescription)")
                throw MCPTransportError.connectionFailed(error.localizedDescription)
            }
        }

        public func send(_ data: Data) async throws {
            guard let stdin = stdinPipe else {
                throw MCPTransportError.closed
            }

            // Ensure newline if using line-delimited
            var messageData = data
            if let str = String(data: data, encoding: .utf8), !str.hasSuffix("\n") {
                messageData.append("\n".data(using: .utf8)!)
            }

            try stdin.fileHandleForWriting.write(contentsOf: messageData)
        }

        public func close() async {
            process?.terminate()
            stdinPipe?.fileHandleForWriting.closeFile()
            stdoutPipe?.fileHandleForReading.readabilityHandler = nil
            stderrPipe?.fileHandleForReading.readabilityHandler = nil
            continuation?.finish()
        }

        // MARK: - Private

        private func emit(data: Data) {
            continuation?.yield(data)
        }

        private func logStderr(_ log: String) {
            logger.debug("Server stderr: \(log)")
        }

        private func handleTermination() {
            logger.info("MCP Server process terminated")
            continuation?.finish()
        }
    }
#else
    // iOS / Other platforms stub
    public actor StdioTransport: MCPTransport {
        nonisolated public let messages: AsyncStream<Data>

        public init(command: String, arguments: [String] = [], environment: [String: String] = [:])
        {
            self.messages = AsyncStream { _ in }
        }

        public func start() async throws {
            throw MCPTransportError.connectionFailed(
                "Stdio transport is not supported on this platform")
        }

        public func send(_ data: Data) async throws {
            throw MCPTransportError.closed
        }

        public func close() async {}
    }
#endif

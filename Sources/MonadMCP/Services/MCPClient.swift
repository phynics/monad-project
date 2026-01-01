import Combine
import Foundation
import OSLog
import Shared

// MARK: - JSON RPC Models

public struct JSONRPCRequest: Codable {
    public var jsonrpc: String = "2.0"
    public let id: Int
    public let method: String
    public let params: AnyCodable?

    public init(id: Int, method: String, params: AnyCodable?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCNotification: Codable {
    public var jsonrpc: String = "2.0"
    public let method: String
    public let params: AnyCodable?

    public init(method: String, params: AnyCodable?) {
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable {
    public var jsonrpc: String = "2.0"
    public let id: Int
    public let result: AnyCodable?
    public let error: JSONRPCError?

    public init(id: Int, result: AnyCodable?, error: JSONRPCError?) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public struct JSONRPCError: Codable, Error {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: AnyCodable?) {
        self.code = code
        self.message = message
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case code, message, data
    }
}

// MARK: - MCP Models

public struct MCPToolDefinition: Codable {
    public let name: String
    public let description: String?
    public let inputSchema: [String: AnyCodable]
}

public struct MCPListToolsResult: Codable {
    public let tools: [MCPToolDefinition]
    public let nextCursor: String?
}

public struct MCPCallToolResult: Codable {
    public let content: [MCPContent]
    public let isError: Bool?
}

public struct MCPContent: Codable {
    public let type: String
    public let text: String?
    public let resource: MCPResource?  // Placeholder for resource type
}

public struct MCPResource: Codable {
    public let uri: String
    public let mimeType: String?
}

// MARK: - Client

public actor MCPClient: ToolProvider {
    private let transport: MCPTransport
    private let logger = Logger(subsystem: "com.monad.assistant", category: "mcp-client")

    private var requestIdCount = 0
    private var pendingRequests: [Int: CheckedContinuation<AnyCodable?, Error>] = [:]
    private var serverCapabilities: AnyCodable?

    private var messageTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    public init(transport: MCPTransport) {
        self.transport = transport
    }

    public func connect() async throws {
        try await transport.start()
        startMessageLoop()
        try await initialize()
    }

    public func disconnect() async {
        messageTask?.cancel()
        await transport.close()
        // Fail all pending
        for continuation in pendingRequests.values {
            continuation.resume(throwing: MCPTransportError.closed)
        }
        pendingRequests.removeAll()
    }

    // MARK: - ToolProvider

    public func getTools() async -> [Tool] {
        do {
            let definitions = try await listTools()
            return definitions.map { MCPTool(client: self, definition: $0) }
        } catch {
            logger.error("Failed to list MCP tools: \(error.localizedDescription)")
            return []
        }
    }

    public func executeToolCall(_ name: String, arguments: [String: AnyCodable]) async throws
        -> String
    {
        let result = try await callTool(name: name, arguments: arguments)
        if let isError = result.isError, isError {
            throw MCPTransportError.readError("MCP Tool Error: \(formatContent(result.content))")
        }
        return formatContent(result.content)
    }

    // MARK: - Internal API

    private func listTools() async throws -> [MCPToolDefinition] {
        let result = try await sendRequest(method: "tools/list", params: nil)

        guard let data = try? JSONEncoder().encode(result),
            let response = try? JSONDecoder().decode(MCPListToolsResult.self, from: data)
        else {
            throw MCPTransportError.readError("Invalid response format for tools/list")
        }

        return response.tools
    }

    private func callTool(name: String, arguments: [String: AnyCodable]) async throws
        -> MCPCallToolResult
    {
        let params: [String: AnyCodable] = [
            "name": AnyCodable(name),
            "arguments": AnyCodable(arguments),
        ]

        let result = try await sendRequest(method: "tools/call", params: AnyCodable(params))

        guard let data = try? JSONEncoder().encode(result),
            let response = try? JSONDecoder().decode(MCPCallToolResult.self, from: data)
        else {
            throw MCPTransportError.readError("Invalid response format for tools/call")
        }

        return response
    }

    private func formatContent(_ content: [MCPContent]) -> String {
        return content.compactMap { item in
            if item.type == "text" {
                return item.text
            }
            return nil
        }.joined(separator: "\n")
    }

    // MARK: - Internal

    private func initialize() async throws {
        let params: [String: Any] = [
            "protocolVersion": "2024-11-05",  // Example
            "capabilities": [
                "roots": ["listChanged": true],
                "sampling": [:],
            ],
            "clientInfo": [
                "name": "monad-assistant",
                "version": "1.0.0",
            ],
        ]

        let result = try await sendRequest(method: "initialize", params: AnyCodable(params))

        // After initialize, we must send notification 'notifications/initialized'
        try await sendNotification(method: "notifications/initialized", params: nil)

        self.serverCapabilities = result
        logger.info("MCP Client initialized")
    }

    private func sendRequest(method: String, params: AnyCodable?) async throws -> AnyCodable? {
        requestIdCount += 1
        let id = requestIdCount

        let request = JSONRPCRequest(id: id, method: method, params: params)
        let data = try JSONEncoder().encode(request)

        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<AnyCodable?, Error>) in
            pendingRequests[id] = continuation

            Task {
                do {
                    try await transport.send(data)
                } catch {
                    pendingRequests.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func sendNotification(method: String, params: AnyCodable?) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        let data = try JSONEncoder().encode(notification)
        try await transport.send(data)
    }

    private func startMessageLoop() {
        messageTask = Task {
            for await data in transport.messages {
                if Task.isCancelled { break }

                // Parse line-delimited JSON or raw JSON chunks
                // For now, assuming complete JSON objects for MVP or handling simple newlines
                // If the transport emits partial chunks, we need a buffer.
                // StdioTransport emits readable chunks. Let's assume for now the server sends newline delimited JSON
                // and the transport might give us multiple lines or partials.
                // IMPORTANT: This part needs robust line splitting if sticking to simple transports.

                guard let content = String(data: data, encoding: .utf8) else { continue }
                let lines = content.split(separator: "\n")

                for line in lines {
                    guard let lineData = String(line).data(using: .utf8) else { continue }
                    await handleMessage(lineData)
                }
            }
        }
    }

    private func handleMessage(_ data: Data) async {
        // Try decoding Response
        if let response = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) {
            if let continuation = pendingRequests.removeValue(forKey: response.id) {
                if let error = response.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: response.result)
                }
            }
            return
        }

        // Handle Request/Notification from server (e.g. logging)
        if let notification = try? JSONDecoder().decode(JSONRPCNotification.self, from: data) {
            logger.debug("Received notification: \(notification.method)")
            // Handle logging, resource updates, etc.
        }
    }
}

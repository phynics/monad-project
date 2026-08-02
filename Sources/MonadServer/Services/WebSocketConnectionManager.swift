import Foundation
import Hummingbird
import HummingbirdWebSocket
import Logging
import PositronicKit
import PKShared
import PKUtilities
import MonadShared

/// Manages WebSocket connections to clients and facilitates server-initiated RPC.
///
/// Wire contract: the server sends `RPCRequest` frames to connected clients (e.g. to
/// execute a `workspace/*` operation on the client side) and expects matching
/// `RPCResponse` frames back, correlated by `id`. The read loop in
/// `WebSocketAPIController` decodes inbound frames as `RPCResponse` and forwards them
/// to `handleResponse`. Pending requests time out after `requestTimeout` and are
/// cancelled with `RPCError.connectionLost` when the client disconnects.
public actor WebSocketConnectionManager: ClientConnectionManagerProtocol {
    private let logger = Logger(label: "com.monad.server.websocket")
    private var connections: [UUID: WebSocketOutboundWriter] = [:]
    private var pendingRequests: [String: CheckedContinuation<AnyCodable, Error>] = [:]
    private var pendingRequestClients: [String: UUID] = [:]

    public let requestTimeout: Duration

    public init(requestTimeout: Duration = .seconds(30)) {
        self.requestTimeout = requestTimeout
    }

    public func addConnection(clientId: UUID, writer: WebSocketOutboundWriter) {
        let cid = ANSIColors.colorize(clientId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightMagenta)
        logger.info("Client connected: \(cid)")
        connections[clientId] = writer
    }

    public func removeConnection(clientId: UUID) {
        let cid = ANSIColors.colorize(clientId.uuidString.prefix(8).lowercased(), color: ANSIColors.brightMagenta)
        logger.info("Client disconnected: \(cid)")
        connections.removeValue(forKey: clientId)

        let pendingIds = pendingRequestClients.compactMap { $0.value == clientId ? $0.key : nil }
        for requestId in pendingIds {
            if let continuation = pendingRequests.removeValue(forKey: requestId) {
                pendingRequestClients.removeValue(forKey: requestId)
                continuation.resume(throwing: RPCError.connectionLost)
            }
        }
    }

    // MARK: - ClientConnectionManagerProtocol

    public func isConnected(clientId: UUID) async -> Bool {
        return connections[clientId] != nil
    }

    public func send<T: Codable & Sendable>(
        method: String,
        params: AnyCodable?,
        expecting _: T.Type,
        to clientId: UUID
    ) async throws -> T {
        guard let writer = connections[clientId] else {
            throw RPCError.connectionLost
        }

        let requestId = UUID().uuidString
        let request = RPCRequest(id: requestId, method: method, params: params)

        guard let data = try? JSONEncoder().encode(request) else {
            throw RPCError.remoteError("Failed to encode request")
        }

        Task {
            do {
                try await writer.write(.text(String(bytes: data, encoding: .utf8) ?? ""))
            } catch {
                if let cont = pendingRequests.removeValue(forKey: requestId) {
                    pendingRequestClients.removeValue(forKey: requestId)
                    cont.resume(throwing: error)
                }
            }
        }

        let responseAny: AnyCodable = try await awaitResponse(requestId: requestId, clientId: clientId)

        // Try to cast directly
        if let casted = responseAny.value as? T {
            return casted
        }

        // Try decoding
        do {
            let data = try JSONSerialization.data(withJSONObject: responseAny.value, options: [])
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            logger.error("Failed to decode response to \(T.self): \(error)")
            throw RPCError.invalidResponse
        }
    }

    /// Registers a pending request and awaits the matching `RPCResponse`.
    /// Used by `send` (after the write) and by tests.
    internal func awaitResponse(
        requestId: String,
        clientId: UUID
    ) async throws -> AnyCodable {
        try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
            pendingRequestClients[requestId] = clientId

            Task {
                try? await Task.sleep(for: requestTimeout)
                if let cont = pendingRequests.removeValue(forKey: requestId) {
                    pendingRequestClients.removeValue(forKey: requestId)
                    cont.resume(throwing: RPCError.timeout)
                }
            }
        }
    }

    public func handleResponse(response: RPCResponse) {
        guard let continuation = pendingRequests.removeValue(forKey: response.id) else {
            return
        }
        pendingRequestClients.removeValue(forKey: response.id)

        if let error = response.error {
            continuation.resume(throwing: RPCError.remoteError(error))
        } else if let result = response.result {
            continuation.resume(returning: result)
        } else {
            // Return void/null representation
            continuation.resume(returning: AnyCodable(NSNull()))
        }
    }
}

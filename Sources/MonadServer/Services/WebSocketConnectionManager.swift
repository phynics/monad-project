import MonadShared
import Foundation
import MonadCore
import Hummingbird
import HummingbirdWebSocket
import Logging

public actor WebSocketConnectionManager: ClientConnectionManagerProtocol {
    private let logger = Logger(label: "com.monad.server.websocket")
    private var connections: [UUID: WebSocketOutboundWriter] = [:]
    private var pendingRequests: [String: CheckedContinuation<AnyCodable, Error>] = [:]
    
    public init() {}
    
    public func addConnection(clientId: UUID, writer: WebSocketOutboundWriter) {
        logger.info("Client connected: \(clientId)")
        connections[clientId] = writer
    }
    
    public func removeConnection(clientId: UUID) {
        logger.info("Client disconnected: \(clientId)")
        connections.removeValue(forKey: clientId)
    }
    
    // MARK: - ClientConnectionManagerProtocol
    
    public func isConnected(clientId: UUID) async -> Bool {
        return connections[clientId] != nil
    }
    
    public func send<T: Codable & Sendable>(
        method: String,
        params: AnyCodable?,
        expecting: T.Type,
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
        
        let responseAny: AnyCodable = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestId] = continuation
            
            Task {
                do {
                    // Send text frame
                    try await writer.write(.text(String(decoding: data, as: UTF8.self)))
                } catch {
                    pendingRequests.removeValue(forKey: requestId)
                    continuation.resume(throwing: error)
                }
            }
        }
        
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
    
    public func handleResponse(response: RPCResponse) {
        guard let continuation = pendingRequests.removeValue(forKey: response.id) else {
            // It might be a request from client to server?
            // For now we only handle Responses to our Requests.
            return
        }
        
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

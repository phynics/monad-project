import MonadShared
import Foundation
import Hummingbird
import HummingbirdWebSocket
import MonadCore
import Logging
import NIOCore
import HTTPTypes

struct WebSocketAPIController<Context>: Sendable where Context: WebSocketRequestContext, Context: RequestContext {
    let connectionManager: WebSocketConnectionManager
    
    func addRoutes(to group: RouterGroup<Context>) {
        group.ws("/v1/connect", onUpgrade: { inbound, outbound, context in
            await self.handle(inbound: inbound, outbound: outbound, context: context)
        })
    }
    
    @Sendable func handle(inbound: WebSocketInboundStream, outbound: WebSocketOutboundWriter, context: WebSocketRouterContext<Context>) async {
        let request = context.request
        // Identify client
        // We expect `x-monad-client-id` header
        guard let clientIdStr = request.headers[HTTPField.Name("x-monad-client-id")!] else {
            // If we can't identify, close.
            return
        }
        
        let clientId: UUID
        if let id = UUID(uuidString: clientIdStr) {
            clientId = id
        } else {
            return
        }
        
        await connectionManager.addConnection(clientId: clientId, writer: outbound)
        
        do {
            // Read loop
            for try await frame in inbound {
                switch frame.opcode {
                case .text:
                     let text = String(buffer: frame.data)
                    // Handle incoming message (RPC Response)
                    if let data = text.data(using: .utf8) {
                        do {
                            let response = try JSONDecoder().decode(RPCResponse.self, from: data)
                            await connectionManager.handleResponse(response: response)
                        } catch {
                            // If it's not a response, maybe it's a request?
                            // For now, log and ignore.
                        }
                    }
                case .binary:
                    break
                default:
                    // Ignore other frames (ping/pong/close are handled by protocol/stream)
                    break
                }
            }
        } catch {
            // socket error
        }
        
        await connectionManager.removeConnection(clientId: clientId)
    }
}

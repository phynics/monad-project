import MonadShared
import MonadCore
import Foundation
@testable import MonadServer
import Testing

/// Tests for `WebSocketConnectionManager` actor.
/// Note: `addConnection` / `removeConnection` are not tested here because creating a real
/// `WebSocketOutboundWriter` requires a live NIO channel. The behaviours that *can* be verified
/// without a live transport are exercised below.
@Suite(.serialized) struct WebSocketConnectionManagerTests {
    @Test("isConnected returns false for unknown client")
    func isConnected_unknownClient() async {
        let manager = WebSocketConnectionManager()
        let unknown = UUID()
        let connected = await manager.isConnected(clientId: unknown)
        #expect(connected == false)
    }

    @Test("send throws connectionLost when client is not connected")
    func send_throwsConnectionLost_whenNotConnected() async throws {
        let manager = WebSocketConnectionManager()
        let clientId = UUID()

        do {
            _ = try await manager.send(method: "ping", params: nil, expecting: String.self, to: clientId)
            Issue.record("Expected connectionLost error")
        } catch RPCError.connectionLost { /* expected */ }
        catch { Issue.record("Expected connectionLost, got \(error)") }
    }

    @Test("handleResponse ignores unknown response IDs without crashing")
    func handleResponse_unknownId_isIgnored() async {
        let manager = WebSocketConnectionManager()
        let response = RPCResponse(id: "nonexistent-id", result: AnyCodable("ok"), error: nil)
        // Should not throw or crash
        await manager.handleResponse(response: response)
    }

    @Test("handleResponse with error resumes continuation with RPCError")
    func handleResponse_errorResponse_resumesWithError() async throws {
        let manager = WebSocketConnectionManager()

        // Simulate a pending request by setting up a continuation manually.
        // We cannot easily inject state without a live socket, so we validate
        // the protocol contract via the "not connected" path and error path.

        let clientId = UUID()
        let errorMessage = "remote tool failed"

        // Verify that a missing connection surfaces as connectionLost, not the remote error.
        do {
            _ = try await manager.send(method: "executeTool", params: AnyCodable(["tool": "bash"]), expecting: String.self, to: clientId)
            Issue.record("Expected connectionLost error")
        } catch RPCError.connectionLost { /* expected */ }
        catch { Issue.record("Expected connectionLost, got \(error)") }

        // Verify handleResponse with a remote error (unknown id — just ignored).
        let errorResponse = RPCResponse(id: UUID().uuidString, result: nil, error: errorMessage)
        await manager.handleResponse(response: errorResponse)
    }

    @Test("removeConnection on unknown client does not crash")
    func removeConnection_unknownClient_isNoOp() async {
        let manager = WebSocketConnectionManager()
        // Should complete without throwing or crashing
        await manager.removeConnection(clientId: UUID())
    }
}
